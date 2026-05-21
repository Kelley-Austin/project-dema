@isTest
private class OpportunityScoreCalculatorTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name      = 'Large Deal',
                AccountId = acc.Id,
                StageName = 'Proposal/Price Quote',
                CloseDate = Date.today().addDays(30),
                Amount    = 750000
            ),
            new Opportunity(
                Name      = 'Small Deal',
                AccountId = acc.Id,
                StageName = 'Needs Analysis',
                CloseDate = Date.today().addDays(60),
                Amount    = 5000
            ),
            new Opportunity(
                Name      = 'No Amount',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(90),
                Amount    = null
            )
        };
        insert opps;

        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 12; i++) {
            tasks.add(new Task(
                WhatId       = opps[0].Id,
                Subject      = 'Call ' + i,
                Status       = 'Completed',
                ActivityDate = Date.today().addDays(-i)
            ));
        }
        insert tasks;
    }

    @isTest
    static void testLargeDeal_highEngagement() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];

        Test.startTest();
        OpportunityScoreCalculator.calculateScores(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity_Score__c score = [
            SELECT Deal_Size_Score__c, Engagement_Score__c, Composite_Score__c
            FROM Opportunity_Score__c
            WHERE Opportunity__c = :opp.Id
        ];

        System.assertEquals(100, score.Deal_Size_Score__c,  '$750k should score 100 for deal size');
        System.assertEquals(80,  score.Engagement_Score__c, '12 tasks should score 80 for engagement');
        // (100*0.40) + (80*0.40) + ((100-0)*0.20) = 40 + 32 + 20 = 92
        System.assertEquals(92,  score.Composite_Score__c,  'Composite should be 92');
    }

    @isTest
    static void testSmallDeal_noEngagement() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Small Deal' LIMIT 1];

        Test.startTest();
        OpportunityScoreCalculator.calculateScores(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity_Score__c score = [
            SELECT Deal_Size_Score__c, Engagement_Score__c, Composite_Score__c
            FROM Opportunity_Score__c
            WHERE Opportunity__c = :opp.Id
        ];

        System.assertEquals(10, score.Deal_Size_Score__c,  '$5000 should score 10');
        System.assertEquals(0,  score.Engagement_Score__c, 'No activities should score 0');
        // (10*0.40) + (0*0.40) + (100*0.20) = 4 + 0 + 20 = 24
        System.assertEquals(24, score.Composite_Score__c);
    }

    @isTest
    static void testNullAmount_scoresZero() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'No Amount' LIMIT 1];

        Test.startTest();
        OpportunityScoreCalculator.calculateScores(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity_Score__c score = [
            SELECT Deal_Size_Score__c
            FROM Opportunity_Score__c
            WHERE Opportunity__c = :opp.Id
        ];

        System.assertEquals(0, score.Deal_Size_Score__c, 'Null amount should score 0');
    }

    @isTest
    static void testGetScoreData_noExistingRecord() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Small Deal' LIMIT 1];

        Test.startTest();
        OpportunityScoreCalculator.ScoreWrapper w = OpportunityScoreCalculator.getScoreData(opp.Id);
        Test.stopTest();

        System.assertEquals(0, w.compositeScore, 'Should return 0 when no score record exists');
    }

    @isTest
    static void testGetScoreData_afterCalculation() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        OpportunityScoreCalculator.calculateScores(new List<Id>{ opp.Id });

        Test.startTest();
        OpportunityScoreCalculator.ScoreWrapper w = OpportunityScoreCalculator.getScoreData(opp.Id);
        Test.stopTest();

        System.assertEquals(92, w.compositeScore);
        System.assertEquals(100, w.dealSizeScore);
        System.assertEquals(80, w.engagementScore);
    }

    @isTest
    static void testRecalculate_nosDuplicates() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];

        Test.startTest();
        OpportunityScoreCalculator.recalculateScore(opp.Id);
        OpportunityScoreCalculator.recalculateScore(opp.Id);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Opportunity_Score__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(1, count, 'Recalculation should upsert, not insert duplicates');
    }

    @isTest
    static void testIntelligenceScore_writtenToOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];

        Test.startTest();
        OpportunityScoreCalculator.calculateScores(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity updated = [SELECT Intelligence_Score__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(92, updated.Intelligence_Score__c, 'Intelligence_Score__c on Opportunity should be updated');
    }

    @isTest
    static void testCompetitiveRisk_reducesComposite() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        OpportunityScoreCalculator.calculateScores(new List<Id>{ opp.Id });

        // Manually set competitive risk to 50, then recalculate
        Opportunity_Score__c score = [SELECT Id FROM Opportunity_Score__c WHERE Opportunity__c = :opp.Id];
        score.Competitive_Risk__c = 50;
        update score;

        Test.startTest();
        OpportunityScoreCalculator.recalculateScore(opp.Id);
        Test.stopTest();

        Opportunity_Score__c updated = [
            SELECT Composite_Score__c, Competitive_Risk__c
            FROM Opportunity_Score__c
            WHERE Opportunity__c = :opp.Id
        ];

        // (100*0.40) + (80*0.40) + ((100-50)*0.20) = 40 + 32 + 10 = 82
        System.assertEquals(50, updated.Competitive_Risk__c, 'Competitive risk should be preserved');
        System.assertEquals(82, updated.Composite_Score__c,  'Competitive risk should reduce composite score');
    }
}
