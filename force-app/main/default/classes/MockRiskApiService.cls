public class MockRiskApiService {

    public class RiskApiRequest {
        public String  lineOfBusiness;
        public String  naicsCodes;
        public Decimal payroll;
        public String  locations;
        public Integer missingItemCount;
        public String  completenessStatus;
    }

    public class RiskApiResponse {
        public Integer       appetiteScore;
        public Integer       fraudScore;
        public Integer       lossFrequencyScore;
        public List<String>  signals;
    }

    public static RiskApiResponse evaluate(RiskApiRequest req) {
        RiskApiResponse resp = new RiskApiResponse();
        resp.signals = new List<String>();

        Integer appetite = 82;
        Integer lossFreq = 30;

        // Payroll-based scoring
        if (req.payroll != null) {
            if (req.payroll > 5000000) {
                appetite -= 25;
                lossFreq += 20;
                resp.signals.add('Very high payroll — elevated loss exposure class');
            } else if (req.payroll > 2000000) {
                appetite -= 10;
                lossFreq += 10;
                resp.signals.add('Payroll exposure is elevated');
            } else if (req.payroll > 0) {
                resp.signals.add('Payroll exposure is moderate');
            }
        }

        // Missing submission items
        if (req.missingItemCount != null && req.missingItemCount > 0) {
            appetite -= req.missingItemCount * 5;
            resp.signals.add('Incomplete submission — ' + req.missingItemCount + ' outstanding item(s)');
        } else if (req.completenessStatus == 'Ready for Review') {
            appetite += 5;
            resp.signals.add('Submission is complete — positive indicator');
        }

        // Multi-state detection
        if (String.isNotBlank(req.locations)) {
            Integer commas = req.locations.length() - req.locations.replace(',', '').length();
            if (commas >= 2) {
                lossFreq += 5;
                resp.signals.add('Multi-state operations detected');
            }
        }

        // NAICS industry appetite check
        if (String.isNotBlank(req.naicsCodes)) {
            String code = req.naicsCodes.split('[,;\\s]+')[0].trim();
            if (code.startsWith('238') || code.startsWith('236') || code.startsWith('237')) {
                resp.signals.add('Construction/contractor NAICS code is within standard appetite');
            } else if (code.startsWith('713') || code.startsWith('722') || code.startsWith('721')) {
                appetite -= 15;
                resp.signals.add('Hospitality/entertainment NAICS — appetite caution advised');
            } else if (String.isNotBlank(code)) {
                resp.signals.add('NAICS code on file — appetite classification complete');
            }
        } else {
            appetite -= 10;
            resp.signals.add('NAICS code not provided — appetite cannot be confirmed');
        }

        resp.appetiteScore      = Math.max(0, Math.min(100, appetite));
        resp.fraudScore         = 12;
        resp.lossFrequencyScore = Math.max(0, Math.min(100, lossFreq));

        return resp;
    }
}
