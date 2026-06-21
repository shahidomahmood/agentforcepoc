/**
 * EvaluateRiskAction
 *
 * Thin @InvocableMethod wrapper that exposes the existing risk-assessment logic to the
 * Agentforce planner. The working logic lives in RiskSignalService.evaluateRisk(...), which is
 * @AuraEnabled only (it drives Glenda's deterministic LWC wizard). Agents can only call Apex
 * marked @InvocableMethod, so this wrapper adds that entry point WITHOUT touching the proven
 * service class — same additive pattern as ExtractSubmissionDataRAGAction.
 *
 * RiskSignalService.evaluateRisk writes Risk_Score__c / Appetite_Score__c / Review_Priority__c /
 * Risk_Summary__c (and the Submission_Risk_Signal__c children) to the record. Those record fields
 * are what the wizard reads, so the wizard lights up identically whether a human clicks the
 * button or the agent calls this action. After the call we re-read the record and return the
 * scores as structured outputs AND in the message, so the conversational agent can report the
 * real numbers rather than a bare "complete".
 */
public with sharing class EvaluateRiskAction {

    public class RiskRequest {
        @InvocableVariable(required=true label='Submission ID')
        public String submissionId;
    }

    public class RiskResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Risk Score')
        public Decimal riskScore;
        @InvocableVariable(label='Appetite Score')
        public Decimal appetiteScore;
        @InvocableVariable(label='Review Priority')
        public String reviewPriority;
    }

    @InvocableMethod(
        label='Evaluate Submission Risk'
        description='Scores an insurance submission against the configured risk-appetite rules and a risk-scoring service, records risk signals, and drafts an underwriter risk brief. Returns the risk score, appetite score and review priority.'
    )
    public static List<RiskResult> evaluateRiskInvocable(List<RiskRequest> requests) {
        List<RiskResult> results = new List<RiskResult>();
        for (RiskRequest req : requests) {
            RiskResult res = new RiskResult();
            try {
                RiskSignalService.evaluateRisk(req.submissionId);

                Submission__c sub = [
                    SELECT Risk_Score__c, Appetite_Score__c, Review_Priority__c
                    FROM   Submission__c
                    WHERE  Id = :req.submissionId
                    LIMIT  1
                ];

                res.success        = true;
                res.riskScore      = sub.Risk_Score__c;
                res.appetiteScore  = sub.Appetite_Score__c;
                res.reviewPriority = sub.Review_Priority__c;
                res.message        = buildMessage(sub);
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    private static String buildMessage(Submission__c sub) {
        String risk     = sub.Risk_Score__c     == null ? 'n/a' : String.valueOf(sub.Risk_Score__c.intValue()) + '/100';
        String appetite = sub.Appetite_Score__c == null ? 'n/a' : String.valueOf(sub.Appetite_Score__c.intValue()) + '/100';
        String priority = String.isBlank(sub.Review_Priority__c) ? 'n/a' : sub.Review_Priority__c;
        return 'Risk assessment complete. Risk Score: ' + risk +
               ', Appetite Score: ' + appetite +
               ', Review Priority: ' + priority + '.';
    }
}
