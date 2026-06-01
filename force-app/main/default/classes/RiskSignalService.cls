public with sharing class RiskSignalService {

    @AuraEnabled(cacheable=true)
    public static List<Submission_Risk_Signal__c> getSignals(String submissionId) {
        return [
            SELECT Signal_Type__c, Severity__c, Score__c, Source__c,
                   Explanation__c, Recommended_Action__c
            FROM   Submission_Risk_Signal__c
            WHERE  Submission__c = :submissionId
            ORDER BY Severity__c, Signal_Type__c
        ];
    }

    @AuraEnabled
    public static void evaluateRisk(String submissionId) {
        // === All SOQL before any callout ===
        List<Risk_Appetite_Rule__mdt> rules = [
            SELECT DeveloperName, Active__c, Line_of_Business__c, Rule_Type__c,
                   Field_API_Name__c, Threshold_Value__c, Document_Keyword__c,
                   Signal_Type__c, Severity__c, Message__c, Recommended_Action__c, Sort_Order__c
            FROM   Risk_Appetite_Rule__mdt
            WHERE  Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];

        // Build field set dynamically from rule definitions
        Set<String> fieldSet = new Set<String>{
            'Id', 'Name', 'Line_of_Business__c', 'Insured_Name__c',
            'Completeness_Status__c', 'NAICS_Codes__c', 'Payroll__c', 'Locations__c'
        };
        for (Risk_Appetite_Rule__mdt rule : rules) {
            if (String.isNotBlank(rule.Field_API_Name__c) && !rule.Field_API_Name__c.contains('.')) {
                fieldSet.add(rule.Field_API_Name__c);
            }
        }

        Submission__c sub = (Submission__c) Database.query(
            'SELECT ' + String.join(new List<String>(fieldSet), ', ') +
            ' FROM Submission__c WHERE Id = :submissionId LIMIT 1'
        );

        List<Missing_Item__c> existingMissingItems = [
            SELECT Id FROM Missing_Item__c WHERE Submission__c = :submissionId
        ];

        List<ContentDocumentLink> docLinks = [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :submissionId
        ];
        List<Id> docIds = new List<Id>();
        for (ContentDocumentLink cdl : docLinks) docIds.add(cdl.ContentDocumentId);

        List<ContentVersion> docs = docIds.isEmpty() ? new List<ContentVersion>() : [
            SELECT Title FROM ContentVersion
            WHERE  ContentDocumentId IN :docIds AND IsLatest = true
        ];

        List<Submission_Risk_Signal__c> oldSignals = [
            SELECT Id FROM Submission_Risk_Signal__c WHERE Submission__c = :submissionId
        ];

        // === Pure computation ===
        String lob = String.isBlank((String) sub.get('Line_of_Business__c'))
            ? 'Workers Comp'
            : (String) sub.get('Line_of_Business__c');

        List<Submission_Risk_Signal__c> newSignals = new List<Submission_Risk_Signal__c>();

        for (Risk_Appetite_Rule__mdt rule : rules) {
            if (String.isNotBlank(rule.Line_of_Business__c) && rule.Line_of_Business__c != lob) continue;
            Submission_Risk_Signal__c sig = evaluateRule(rule, sub, docs);
            if (sig != null) {
                sig.Submission__c = submissionId;
                sig.Source__c     = 'Local Rule';
                newSignals.add(sig);
            }
        }

        MockRiskApiService.RiskApiRequest apiReq = new MockRiskApiService.RiskApiRequest();
        apiReq.lineOfBusiness     = lob;
        apiReq.naicsCodes         = (String)  sub.get('NAICS_Codes__c');
        apiReq.payroll            = (Decimal)  sub.get('Payroll__c');
        apiReq.locations          = (String)  sub.get('Locations__c');
        apiReq.missingItemCount   = existingMissingItems.size();
        apiReq.completenessStatus = (String)  sub.get('Completeness_Status__c');

        MockRiskApiService.RiskApiResponse apiResp = MockRiskApiService.evaluate(apiReq);

        for (String txt : apiResp.signals) {
            newSignals.add(new Submission_Risk_Signal__c(
                Submission__c    = submissionId,
                Signal_Type__c   = txt.length() > 255 ? txt.left(255) : txt,
                Severity__c      = 'Medium',
                Score__c         = apiResp.appetiteScore,
                Source__c        = 'External API',
                Explanation__c   = 'Returned by external risk scoring service'
            ));
        }

        Integer riskScore    = calculateRiskScore(newSignals);
        Integer appetiteScore = apiResp.appetiteScore;
        String  priority     = calculatePriority(appetiteScore, riskScore, newSignals);

        // === Agentforce callout — must precede DML ===
        String riskSummary = generateRiskSummary(sub, newSignals, apiResp, lob);

        // === All DML last ===
        if (!oldSignals.isEmpty()) delete oldSignals;
        if (!newSignals.isEmpty()) insert newSignals;

        sub.Appetite_Score__c  = appetiteScore;
        sub.Risk_Score__c      = riskScore;
        sub.Review_Priority__c = priority;
        sub.Risk_Summary__c    = riskSummary;
        update sub;
    }

    private static Submission_Risk_Signal__c evaluateRule(
        Risk_Appetite_Rule__mdt rule, Submission__c sub, List<ContentVersion> docs
    ) {
        Boolean triggered = false;

        if (rule.Rule_Type__c == 'FieldThreshold') {
            Object val = sub.get(rule.Field_API_Name__c);
            if (val != null) {
                try {
                    Decimal num = Decimal.valueOf(String.valueOf(val));
                    triggered = (rule.Threshold_Value__c != null && num > rule.Threshold_Value__c);
                } catch (Exception e) { /* non-numeric field — skip */ }
            }
        } else if (rule.Rule_Type__c == 'FieldBlank') {
            Object val = sub.get(rule.Field_API_Name__c);
            triggered = (val == null || String.isBlank(String.valueOf(val)));
        } else if (rule.Rule_Type__c == 'FieldNotBlank') {
            Object val = sub.get(rule.Field_API_Name__c);
            triggered = (val != null && String.isNotBlank(String.valueOf(val)));
        } else if (rule.Rule_Type__c == 'DocumentMissing') {
            triggered = true;
            if (String.isNotBlank(rule.Document_Keyword__c)) {
                String kw = rule.Document_Keyword__c.toLowerCase();
                for (ContentVersion cv : docs) {
                    if (cv.Title.toLowerCase().contains(kw)) { triggered = false; break; }
                }
            }
        } else if (rule.Rule_Type__c == 'DocumentPresent') {
            if (String.isNotBlank(rule.Document_Keyword__c)) {
                String kw = rule.Document_Keyword__c.toLowerCase();
                for (ContentVersion cv : docs) {
                    if (cv.Title.toLowerCase().contains(kw)) { triggered = true; break; }
                }
            }
        }

        if (!triggered) return null;

        return new Submission_Risk_Signal__c(
            Signal_Type__c      = rule.Signal_Type__c,
            Severity__c         = rule.Severity__c,
            Explanation__c      = rule.Message__c,
            Recommended_Action__c = rule.Recommended_Action__c
        );
    }

    private static Integer calculateRiskScore(List<Submission_Risk_Signal__c> signals) {
        Integer score = 50;
        for (Submission_Risk_Signal__c sig : signals) {
            if (sig.Source__c != 'Local Rule') continue;
            if      (sig.Severity__c == 'High')     score += 15;
            else if (sig.Severity__c == 'Medium')   score += 8;
            else if (sig.Severity__c == 'Positive') score -= 10;
        }
        return Math.max(0, Math.min(100, score));
    }

    private static String calculatePriority(
        Integer appetiteScore, Integer riskScore, List<Submission_Risk_Signal__c> signals
    ) {
        for (Submission_Risk_Signal__c sig : signals) {
            if (sig.Severity__c == 'High') return 'High Priority';
        }
        if (appetiteScore < 60 || riskScore > 75) return 'High Priority';
        if (appetiteScore < 75 || riskScore > 50) return 'Standard Review';
        return 'Low Priority';
    }

    private static String generateRiskSummary(
        Submission__c sub, List<Submission_Risk_Signal__c> signals,
        MockRiskApiService.RiskApiResponse apiResp, String lob
    ) {
        try {
            List<String> lines = new List<String>();
            for (Submission_Risk_Signal__c sig : signals) {
                lines.add('[' + sig.Severity__c + '] ' + sig.Signal_Type__c +
                    (String.isNotBlank(sig.Explanation__c) ? ': ' + sig.Explanation__c : ''));
            }
            String signalText = lines.isEmpty() ? 'No signals detected.' : String.join(lines, '\n');

            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            input.isPreview = false;

            Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue v;

            v = new ConnectApi.WrappedValue();
            v.value = String.isBlank((String) sub.get('Insured_Name__c')) ? 'Unknown Insured' : (String) sub.get('Insured_Name__c');
            params.put('Input:InsuredName', v);

            v = new ConnectApi.WrappedValue();
            v.value = lob;
            params.put('Input:LineOfBusiness', v);

            v = new ConnectApi.WrappedValue();
            v.value = signalText;
            params.put('Input:RiskSignals', v);

            v = new ConnectApi.WrappedValue();
            v.value = 'Appetite Score: ' + apiResp.appetiteScore +
                      ', Fraud Score: ' + apiResp.fraudScore +
                      ', Loss Frequency Score: ' + apiResp.lossFrequencyScore;
            params.put('Input:Scores', v);

            input.inputParams = params;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Submission_Risk_Summary', input);

            return resp.generations[0].text;

        } catch (Exception e) {
            return buildFallbackSummary(sub, signals, apiResp, lob);
        }
    }

    private static String buildFallbackSummary(
        Submission__c sub, List<Submission_Risk_Signal__c> signals,
        MockRiskApiService.RiskApiResponse apiResp, String lob
    ) {
        String name = String.isBlank((String) sub.get('Insured_Name__c')) ? 'the insured' : (String) sub.get('Insured_Name__c');
        List<String> highSigs = new List<String>(), medSigs = new List<String>(), posSigs = new List<String>();
        for (Submission_Risk_Signal__c sig : signals) {
            if      (sig.Severity__c == 'High')     highSigs.add(sig.Signal_Type__c);
            else if (sig.Severity__c == 'Medium')   medSigs.add(sig.Signal_Type__c);
            else if (sig.Severity__c == 'Positive') posSigs.add(sig.Signal_Type__c);
        }

        List<String> parts = new List<String>{
            'Risk Assessment — ' + name + ' (' + lob + ')',
            'Appetite Score: ' + apiResp.appetiteScore + '/100 | Fraud Score: ' + apiResp.fraudScore + '/100 | Loss Frequency: ' + apiResp.lossFrequencyScore + '/100'
        };
        if (!highSigs.isEmpty())  parts.add('High Risk: '     + String.join(highSigs, '; '));
        if (!medSigs.isEmpty())   parts.add('Medium Risk: '   + String.join(medSigs, '; '));
        if (!posSigs.isEmpty())   parts.add('Positive: '      + String.join(posSigs, '; '));
        return String.join(parts, '\n');
    }
}
