public with sharing class OpportunityScoreCalculator {

    // Composite weights: 40% deal size, 40% engagement, 20% inverted competitive risk
    private static final Decimal DEAL_WEIGHT       = 0.40;
    private static final Decimal ENGAGEMENT_WEIGHT = 0.40;
    private static final Decimal RISK_WEIGHT       = 0.20;

    @InvocableMethod(label='Calculate Opportunity Score'
                     description='Calculates deal size, engagement, and composite scores for opportunities')
    public static void calculateScores(List<Id> opportunityIds) {
        calculateAndSave(new Set<Id>(opportunityIds));
    }

    @AuraEnabled
    public static void recalculateScore(Id opportunityId) {
        calculateAndSave(new Set<Id>{ opportunityId });
    }

    @AuraEnabled(cacheable=true)
    public static ScoreWrapper getScoreData(Id opportunityId) {
        List<Opportunity_Score__c> scores = [
            SELECT Deal_Size_Score__c, Engagement_Score__c, Competitive_Risk__c, Composite_Score__c
            FROM Opportunity_Score__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (scores.isEmpty()) {
            return new ScoreWrapper(0, 0, 0, 0);
        }

        Opportunity_Score__c s = scores[0];
        return new ScoreWrapper(
            s.Deal_Size_Score__c     ?? 0,
            s.Engagement_Score__c    ?? 0,
            s.Competitive_Risk__c    ?? 0,
            s.Composite_Score__c     ?? 0
        );
    }

    private static void calculateAndSave(Set<Id> opportunityIds) {
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, Amount
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);

        Date ninetyDaysAgo = Date.today().addDays(-90);
        Map<Id, Integer> activityCount = new Map<Id, Integer>();
        for (Id oppId : opportunityIds) {
            activityCount.put(oppId, 0);
        }

        for (AggregateResult ar : [
            SELECT WhatId, COUNT(Id) cnt
            FROM Task
            WHERE WhatId IN :opportunityIds
              AND ActivityDate >= :ninetyDaysAgo
            GROUP BY WhatId
        ]) {
            Id whatId = (Id) ar.get('WhatId');
            activityCount.put(whatId, (Integer) ar.get('cnt'));
        }

        DateTime cutoff = DateTime.newInstance(ninetyDaysAgo, Time.newInstance(0, 0, 0, 0));
        for (AggregateResult ar : [
            SELECT WhatId, COUNT(Id) cnt
            FROM Event
            WHERE WhatId IN :opportunityIds
              AND ActivityDateTime >= :cutoff
            GROUP BY WhatId
        ]) {
            Id whatId = (Id) ar.get('WhatId');
            activityCount.put(whatId, (activityCount.get(whatId) ?? 0) + (Integer) ar.get('cnt'));
        }

        Map<Id, Opportunity_Score__c> existingScores = new Map<Id, Opportunity_Score__c>();
        for (Opportunity_Score__c s : [
            SELECT Id, Opportunity__c, Competitive_Risk__c
            FROM Opportunity_Score__c
            WHERE Opportunity__c IN :opportunityIds
        ]) {
            existingScores.put(s.Opportunity__c, s);
        }

        List<Opportunity_Score__c> toUpsert     = new List<Opportunity_Score__c>();
        List<Opportunity>          oppsToUpdate = new List<Opportunity>();

        for (Id oppId : opportunityIds) {
            Opportunity opp = oppMap.get(oppId);
            if (opp == null) {
                continue;
            }

            Decimal dealScore       = scoreDealSize(opp.Amount);
            Decimal engagementScore = scoreEngagement(activityCount.get(oppId) ?? 0);

            Opportunity_Score__c scoreRec = existingScores.containsKey(oppId)
                ? existingScores.get(oppId)
                : new Opportunity_Score__c(Opportunity__c = oppId);

            Decimal competitiveRisk = scoreRec.Competitive_Risk__c ?? 0;
            Decimal composite       = calculateComposite(dealScore, engagementScore, competitiveRisk);

            scoreRec.Deal_Size_Score__c  = dealScore;
            scoreRec.Engagement_Score__c = engagementScore;
            scoreRec.Composite_Score__c  = composite;

            toUpsert.add(scoreRec);
            oppsToUpdate.add(new Opportunity(Id = oppId, Intelligence_Score__c = composite));
        }

        upsert toUpsert;
        update oppsToUpdate;
    }

    private static Decimal scoreDealSize(Decimal amount) {
        if (amount == null || amount <= 0) return 0;
        if (amount >= 500000) return 100;
        if (amount >= 100000) return 75;
        if (amount >= 50000)  return 50;
        if (amount >= 10000)  return 25;
        return 10;
    }

    private static Decimal scoreEngagement(Integer count) {
        if (count <= 0)  return 0;
        if (count >= 15) return 100;
        if (count >= 10) return 80;
        if (count >= 6)  return 60;
        if (count >= 3)  return 40;
        return 20;
    }

    private static Decimal calculateComposite(Decimal deal, Decimal engagement, Decimal risk) {
        return (deal       * DEAL_WEIGHT)
             + (engagement * ENGAGEMENT_WEIGHT)
             + ((100 - risk) * RISK_WEIGHT);
    }

    public class ScoreWrapper {
        @AuraEnabled public Decimal dealSizeScore;
        @AuraEnabled public Decimal engagementScore;
        @AuraEnabled public Decimal competitiveRisk;
        @AuraEnabled public Decimal compositeScore;

        public ScoreWrapper(Decimal d, Decimal e, Decimal r, Decimal c) {
            dealSizeScore   = d;
            engagementScore = e;
            competitiveRisk = r;
            compositeScore  = c;
        }
    }
}
