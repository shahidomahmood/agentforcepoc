public with sharing class UnderwriterDashboardController {

    // ─── Wrapper classes ────────────────────────────────────────────────────

    public class DashboardData {
        @AuraEnabled public Integer              totalSubmissions    = 0;
        @AuraEnabled public Integer              newSubmissions      = 0;
        @AuraEnabled public Integer              documentsReceived   = 0;
        @AuraEnabled public Integer              pendingReview       = 0;
        @AuraEnabled public Integer              missingInformation  = 0;
        @AuraEnabled public Integer              highRiskSubmissions = 0;
        @AuraEnabled public List<ChartEntry>     intakeByDay         = new List<ChartEntry>();
        @AuraEnabled public List<ChartEntry>     statusBreakdown     = new List<ChartEntry>();
        @AuraEnabled public List<ChartEntry>     documentsByType     = new List<ChartEntry>();
        @AuraEnabled public List<RiskBucket>     riskDistribution    = new List<RiskBucket>();
        @AuraEnabled public List<MissingInfoRow> missingInfoQueue    = new List<MissingInfoRow>();
        @AuraEnabled public List<RecentRow>      recentActivity      = new List<RecentRow>();
    }

    public class ChartEntry {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer count;
        @AuraEnabled public String  barStyle; // e.g. "width: 75%"
        @AuraEnabled public String  barCss;
    }

    public class RiskBucket {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer count;
        @AuraEnabled public String  tileCss;
    }

    public class MissingInfoRow {
        @AuraEnabled public String   submissionId;
        @AuraEnabled public String   submissionName;
        @AuraEnabled public Integer  missingCount;
        @AuraEnabled public String   brokerName;
        @AuraEnabled public DateTime receivedDate;
    }

    public class RecentRow {
        @AuraEnabled public String   submissionId;
        @AuraEnabled public String   name;
        @AuraEnabled public String   brokerName;
        @AuraEnabled public DateTime receivedDate;
        @AuraEnabled public String   status;
        @AuraEnabled public String   reviewPriority;
    }

    // ─── Public API ─────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData d = new DashboardData();

        // ── KPI counts ──────────────────────────────────────────────────────

        d.totalSubmissions = [SELECT COUNT() FROM Submission__c];

        DateTime sevenDaysAgo = DateTime.now().addDays(-7);
        d.newSubmissions = [
            SELECT COUNT() FROM Submission__c
            WHERE Received_Date__c >= :sevenDaysAgo
        ];

        // Collect submission IDs once; reused for ContentDocumentLink queries
        List<Id> subIds = new List<Id>();
        for (Submission__c s : [SELECT Id FROM Submission__c]) {
            subIds.add(s.Id);
        }

        d.documentsReceived = subIds.isEmpty() ? 0 : [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId IN :subIds
        ];

        d.pendingReview = [
            SELECT COUNT() FROM Submission__c
            WHERE Completeness_Status__c = 'Ready for Review'
        ];

        d.missingInformation = [
            SELECT COUNT() FROM Submission__c
            WHERE Completeness_Status__c = 'Additional Information Required'
        ];

        d.highRiskSubmissions = [
            SELECT COUNT() FROM Submission__c
            WHERE Review_Priority__c = 'High Priority'
        ];

        // ── Chart data ──────────────────────────────────────────────────────

        d.intakeByDay      = buildIntakeByDay();
        d.statusBreakdown  = buildStatusBreakdown(d.totalSubmissions);
        d.documentsByType  = buildDocumentsByType(subIds);
        d.riskDistribution = buildRiskDistribution();

        // ── Tables ──────────────────────────────────────────────────────────

        d.missingInfoQueue = buildMissingInfoQueue();
        d.recentActivity   = buildRecentActivity();

        return d;
    }

    // ─── Private helpers ────────────────────────────────────────────────────

    private static List<ChartEntry> buildIntakeByDay() {
        DateTime thirtyDaysAgo = DateTime.now().addDays(-30);

        List<AggregateResult> results = [
            SELECT DAY_ONLY(Received_Date__c) dayKey, COUNT(Id) cnt
            FROM   Submission__c
            WHERE  Received_Date__c >= :thirtyDaysAgo
            GROUP BY DAY_ONLY(Received_Date__c)
            ORDER BY DAY_ONLY(Received_Date__c) ASC
        ];

        Integer maxCount = 1;
        List<ChartEntry> entries = new List<ChartEntry>();

        for (AggregateResult ar : results) {
            Integer cnt = (Integer) ar.get('cnt');
            if (cnt > maxCount) maxCount = cnt;
            ChartEntry e = new ChartEntry();
            e.label  = String.valueOf(ar.get('dayKey')); // YYYY-MM-DD
            e.count  = cnt;
            e.barCss = 'chart-bar bar-intake';
            entries.add(e);
        }

        for (ChartEntry e : entries) {
            e.barStyle = 'width: ' + (Integer) Math.round((e.count * 100.0) / maxCount) + '%';
        }

        return entries;
    }

    private static List<ChartEntry> buildStatusBreakdown(Integer total) {
        Map<String, Integer> counts = new Map<String, Integer>{
            'New'                             => 0,
            'Processing'                      => 0,
            'Additional Information Required' => 0,
            'Ready for Review'                => 0,
            'Completed'                       => 0
        };

        for (AggregateResult ar : [
            SELECT Completeness_Status__c cs, Extraction_Status__c es, COUNT(Id) cnt
            FROM   Submission__c
            GROUP BY Completeness_Status__c, Extraction_Status__c
        ]) {
            String  cs  = (String)  ar.get('cs');
            String  es  = (String)  ar.get('es');
            Integer cnt = (Integer) ar.get('cnt');
            String  bucket = deriveStatusBucket(cs, es);
            counts.put(bucket, counts.get(bucket) + cnt);
        }

        Integer denom   = Math.max(1, total);
        List<String[]> specs = new List<String[]>{
            new String[]{ 'New',                             'New',                'bar-new'        },
            new String[]{ 'Processing',                      'Processing',         'bar-processing'  },
            new String[]{ 'Additional Information Required', 'Missing Info',       'bar-missing'     },
            new String[]{ 'Ready for Review',                'Ready for Review',   'bar-ready'       },
            new String[]{ 'Completed',                       'Completed',          'bar-completed'   }
        };

        List<ChartEntry> entries = new List<ChartEntry>();
        for (String[] spec : specs) {
            Integer cnt = counts.get(spec[0]);
            ChartEntry e = new ChartEntry();
            e.label    = spec[1];
            e.count    = cnt;
            e.barStyle = 'width: ' + (Integer) Math.round((cnt * 100.0) / denom) + '%';
            e.barCss   = 'chart-bar ' + spec[2];
            entries.add(e);
        }
        return entries;
    }

    private static String deriveStatusBucket(String cs, String es) {
        if (cs == 'Ready for Review')                return 'Ready for Review';
        if (cs == 'Additional Information Required') return 'Additional Information Required';
        if (es == 'In Progress')                     return 'Processing';
        if (es == 'Completed' || es == 'Failed')     return 'Processing';
        return 'New';
    }

    private static List<ChartEntry> buildDocumentsByType(List<Id> subIds) {
        Map<String, Integer> counts = new Map<String, Integer>{
            'ACORD 125'    => 0,
            'ACORD 130'    => 0,
            'Loss Runs'    => 0,
            'Supplemental' => 0,
            'Other'        => 0
        };

        if (!subIds.isEmpty()) {
            for (ContentDocumentLink cdl : [
                SELECT ContentDocument.Title
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId IN :subIds
                LIMIT  2000
            ]) {
                String title = cdl.ContentDocument.Title == null
                    ? '' : cdl.ContentDocument.Title.toLowerCase();
                String bucket;
                if      (title.contains('acord') && title.contains('125')) bucket = 'ACORD 125';
                else if (title.contains('acord') && title.contains('130')) bucket = 'ACORD 130';
                else if (title.contains('loss')  || title.contains('run')) bucket = 'Loss Runs';
                else if (title.contains('supp')  || title.contains('app')) bucket = 'Supplemental';
                else                                                        bucket = 'Other';
                counts.put(bucket, counts.get(bucket) + 1);
            }
        }

        Integer maxCount = 1;
        for (Integer v : counts.values()) { if (v > maxCount) maxCount = v; }

        List<String> order = new List<String>{
            'ACORD 125', 'ACORD 130', 'Loss Runs', 'Supplemental', 'Other'
        };
        List<ChartEntry> entries = new List<ChartEntry>();
        for (String key : order) {
            Integer cnt = counts.get(key);
            ChartEntry e = new ChartEntry();
            e.label    = key;
            e.count    = cnt;
            e.barStyle = 'width: ' + (Integer) Math.round((cnt * 100.0) / maxCount) + '%';
            e.barCss   = 'chart-bar bar-doc';
            entries.add(e);
        }
        return entries;
    }

    private static List<RiskBucket> buildRiskDistribution() {
        Map<String, Integer> counts = new Map<String, Integer>{
            'High Priority'  => 0,
            'Standard Review'=> 0,
            'Low Priority'   => 0
        };

        for (AggregateResult ar : [
            SELECT Review_Priority__c priority, COUNT(Id) cnt
            FROM   Submission__c
            WHERE  Review_Priority__c != null
            GROUP BY Review_Priority__c
        ]) {
            String p = (String) ar.get('priority');
            if (counts.containsKey(p)) {
                counts.put(p, (Integer) ar.get('cnt'));
            }
        }

        List<RiskBucket> buckets = new List<RiskBucket>();
        buckets.add(makeRiskBucket('High Risk',   counts.get('High Priority'),   'risk-tile risk-high'));
        buckets.add(makeRiskBucket('Medium Risk',  counts.get('Standard Review'), 'risk-tile risk-medium'));
        buckets.add(makeRiskBucket('Low Risk',    counts.get('Low Priority'),    'risk-tile risk-low'));
        return buckets;
    }

    private static RiskBucket makeRiskBucket(String label, Integer count, String css) {
        RiskBucket b = new RiskBucket();
        b.label   = label;
        b.count   = count;
        b.tileCss = css;
        return b;
    }

    private static List<MissingInfoRow> buildMissingInfoQueue() {
        Map<Id, Integer> missingCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Submission__c subId, COUNT(Id) cnt
            FROM   Missing_Item__c
            WHERE  Is_Resolved__c = false
            GROUP BY Submission__c
        ]) {
            missingCounts.put((Id) ar.get('subId'), (Integer) ar.get('cnt'));
        }

        List<MissingInfoRow> rows = new List<MissingInfoRow>();
        for (Submission__c s : [
            SELECT Id, Name, Broker_Name__c, Received_Date__c
            FROM   Submission__c
            WHERE  Completeness_Status__c = 'Additional Information Required'
            ORDER BY Received_Date__c ASC NULLS LAST
            LIMIT  10
        ]) {
            MissingInfoRow r = new MissingInfoRow();
            r.submissionId   = s.Id;
            r.submissionName = s.Name;
            r.missingCount   = missingCounts.containsKey(s.Id) ? missingCounts.get(s.Id) : 0;
            r.brokerName     = String.isBlank(s.Broker_Name__c) ? '—' : s.Broker_Name__c;
            r.receivedDate   = s.Received_Date__c;
            rows.add(r);
        }
        return rows;
    }

    private static List<RecentRow> buildRecentActivity() {
        List<RecentRow> rows = new List<RecentRow>();
        for (Submission__c s : [
            SELECT Id, Name, Broker_Name__c, Received_Date__c,
                   Completeness_Status__c, Extraction_Status__c, Review_Priority__c
            FROM   Submission__c
            ORDER BY Received_Date__c DESC NULLS LAST
            LIMIT  10
        ]) {
            RecentRow r = new RecentRow();
            r.submissionId   = s.Id;
            r.name           = s.Name;
            r.brokerName     = String.isBlank(s.Broker_Name__c) ? '—' : s.Broker_Name__c;
            r.receivedDate   = s.Received_Date__c;
            r.reviewPriority = String.isBlank(s.Review_Priority__c) ? '—' : s.Review_Priority__c;
            r.status         = deriveStatusLabel(s.Completeness_Status__c, s.Extraction_Status__c);
            rows.add(r);
        }
        return rows;
    }

    private static String deriveStatusLabel(String cs, String es) {
        if (cs == 'Ready for Review')                return 'Ready for Review';
        if (cs == 'Additional Information Required') return 'Missing Information';
        if (es == 'In Progress')                     return 'Processing';
        if (es == 'Completed' || es == 'Failed')     return 'Processing';
        return 'New';
    }
}
