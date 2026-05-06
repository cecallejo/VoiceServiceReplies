@IsTest
private class GroundedRepliesVoiceControllerTest {
    @IsTest
    static void testGenerateRepliesValidatesInputs() {
        Test.startTest();
        GroundedRepliesVoiceController.RecommendationResponse r1 =
            GroundedRepliesVoiceController.generateReplies(null, 'FlowA', 'FlowB');
        GroundedRepliesVoiceController.RecommendationResponse r2 =
            GroundedRepliesVoiceController.generateReplies(
                Id.valueOf('001000000000001AAA'),
                null,
                'FlowB'
            );
        GroundedRepliesVoiceController.RecommendationResponse r3 =
            GroundedRepliesVoiceController.generateReplies(
                Id.valueOf('001000000000001AAA'),
                'FlowA',
                null
            );
        Test.stopTest();

        System.assertEquals(false, r1.success);
        System.assert(String.isNotBlank(r1.errorMessage));
        System.assertEquals(false, r2.success);
        System.assert(String.isNotBlank(r2.errorMessage));
        System.assertEquals(false, r3.success);
        System.assert(String.isNotBlank(r3.errorMessage));
    }

    @IsTest
    static void testFetchTranscriptValidatesInputs() {
        Test.startTest();
        Boolean threwNull = false;
        try {
            GroundedRepliesVoiceController.fetchTranscript(null, 'FlowA');
        } catch (Exception e) {
            threwNull = true;
        }
        Boolean threwBlank = false;
        try {
            GroundedRepliesVoiceController.fetchTranscript(
                Id.valueOf('001000000000001AAA'),
                null
            );
        } catch (Exception e) {
            threwBlank = true;
        }
        Test.stopTest();

        System.assertEquals(true, threwNull);
        System.assertEquals(true, threwBlank);
    }

    @IsTest
    static void testParseRecommendationsScenarios() {
        List<GroundedRepliesVoiceController.RecommendationItem> blankResult =
            GroundedRepliesVoiceController.parseRecommendations(null);
        System.assertEquals(0, blankResult.size());

        List<GroundedRepliesVoiceController.RecommendationItem> plainResult =
            GroundedRepliesVoiceController.parseRecommendations('texto simples');
        System.assertEquals(1, plainResult.size());
        System.assertEquals('texto simples', plainResult[0].text);

        List<GroundedRepliesVoiceController.RecommendationItem> invalidJsonResult =
            GroundedRepliesVoiceController.parseRecommendations('{"foo":"bar"}');
        System.assertEquals(1, invalidJsonResult.size());
        System.assert(invalidJsonResult[0].text.contains('"foo"'));

        String validJson =
            '{"responses":[{"response":"Resposta 1","source":{"sourceRecordId":"ka000000000000000","dataSourceObject":"KnowledgeArticleVersion"}},{"response":"Resposta 2","source":{"sourceRecordId":"001000000000000AAA","dataSourceObject":"Account"}}]}';
        List<GroundedRepliesVoiceController.RecommendationItem> structuredResult =
            GroundedRepliesVoiceController.parseRecommendations(validJson);
        System.assertEquals(2, structuredResult.size());
        System.assertEquals('Resposta 1', structuredResult[0].text);
        System.assertEquals('ka000000000000000', structuredResult[0].sourceRecordId);
        System.assertEquals('KnowledgeArticleVersion', structuredResult[0].dataSourceObject);
    }
}
