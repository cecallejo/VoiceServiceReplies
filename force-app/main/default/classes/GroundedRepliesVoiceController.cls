public with sharing class GroundedRepliesVoiceController {
    public class RecommendationItem {
        @AuraEnabled public String text;
        @AuraEnabled public String sourceRecordId;
        @AuraEnabled public String dataSourceObject;
        @AuraEnabled public String articleTitle;
    }

    public class RecommendationResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String transcript;
        @AuraEnabled public String rawPromptResponse;
        @AuraEnabled public List<RecommendationItem> recommendations;
        @AuraEnabled public String errorMessage;
    }

    @AuraEnabled
    public static RecommendationResponse generateReplies(
        Id voiceCallId,
        String transcriptFlowName,
        String groundingFlowName
    ) {
        RecommendationResponse result = new RecommendationResponse();
        result.success = false;
        result.recommendations = new List<RecommendationItem>();

        try {
            if (voiceCallId == null) {
                throw new AuraHandledException('VoiceCall Id is required.');
            }
            if (String.isBlank(transcriptFlowName)) {
                throw new AuraHandledException('Transcript Flow Name is required.');
            }
            if (String.isBlank(groundingFlowName)) {
                throw new AuraHandledException('Grounding Flow Name is required.');
            }

            String transcript = runTranscriptFlow(voiceCallId, transcriptFlowName);
            result.transcript = transcript;
            if (String.isBlank(transcript)) {
                throw new AuraHandledException('Transcript flow returned an empty transcript.');
            }

            String promptResponse = runGroundingFlow(voiceCallId, transcript, groundingFlowName);
            result.rawPromptResponse = promptResponse;
            result.recommendations = parseRecommendations(promptResponse);
            result.success = true;
        } catch (Exception e) {
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    private static String runTranscriptFlow(Id voiceCallId, String flowName) {
        Map<String, Object> inputs = new Map<String, Object>{
            'recordId' => (String) voiceCallId,
            'voiceCallId' => (String) voiceCallId
        };
        Flow.Interview interview = Flow.Interview.createInterview(flowName, inputs);
        interview.start();

        List<String> outputVariables = new List<String>{
            'transcriptText',
            'conversationTranscript',
            'Transcript',
            'transcript'
        };
        for (String varName : outputVariables) {
            Object value = interview.getVariableValue(varName);
            if (value != null && String.isNotBlank(String.valueOf(value))) {
                return String.valueOf(value);
            }
        }
        return null;
    }

    private static String runGroundingFlow(Id voiceCallId, String transcript, String flowName) {
        Map<String, Object> inputs = new Map<String, Object>{
            'recordId' => (String) voiceCallId,
            'voiceCallId' => (String) voiceCallId,
            'transcript' => transcript,
            'Transcript' => transcript
        };
        Flow.Interview interview = Flow.Interview.createInterview(flowName, inputs);
        interview.start();

        List<String> outputVariables = new List<String>{
            'promptResponse',
            'Prompt_Response',
            'response',
            'Result'
        };
        for (String varName : outputVariables) {
            Object value = interview.getVariableValue(varName);
            if (value != null && String.isNotBlank(String.valueOf(value))) {
                return String.valueOf(value);
            }
        }
        return null;
    }

    private static List<RecommendationItem> parseRecommendations(String rawResponse) {
        List<RecommendationItem> output = new List<RecommendationItem>();
        if (String.isBlank(rawResponse)) {
            return output;
        }

        Object parsed = JSON.deserializeUntyped(rawResponse);
        if (!(parsed instanceof Map<String, Object>)) {
            RecommendationItem fallback = new RecommendationItem();
            fallback.text = rawResponse;
            output.add(fallback);
            return output;
        }

        Map<String, Object> root = (Map<String, Object>) parsed;
        if (!root.containsKey('responses') || !(root.get('responses') instanceof List<Object>)) {
            RecommendationItem fallback = new RecommendationItem();
            fallback.text = rawResponse;
            output.add(fallback);
            return output;
        }

        for (Object row : (List<Object>) root.get('responses')) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> responseItem = (Map<String, Object>) row;
            RecommendationItem recommendation = new RecommendationItem();
            recommendation.text = readString(responseItem, 'response');
            if (responseItem.containsKey('source') && responseItem.get('source') instanceof Map<String, Object>) {
                Map<String, Object> source = (Map<String, Object>) responseItem.get('source');
                recommendation.sourceRecordId = readString(source, 'sourceRecordId');
                recommendation.dataSourceObject = readString(source, 'dataSourceObject');
            }
            if (String.isNotBlank(recommendation.text)) {
                output.add(recommendation);
            }
        }

        enrichKnowledgeTitles(output);
        return output;
    }

    private static void enrichKnowledgeTitles(List<RecommendationItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        Set<Id> kavIds = new Set<Id>();
        for (RecommendationItem item : items) {
            if (String.isBlank(item.sourceRecordId)) {
                continue;
            }
            // Knowledge Article Version Ids start with ka0.
            if (!item.sourceRecordId.startsWith('ka0')) {
                continue;
            }
            try {
                kavIds.add((Id) item.sourceRecordId);
            } catch (Exception ignored) {
                // Ignore invalid ids coming from external sources.
            }
        }

        if (kavIds.isEmpty()) {
            return;
        }

        Map<Id, KnowledgeArticleVersion> kavById = new Map<Id, KnowledgeArticleVersion>(
            [
                SELECT Id, Title
                FROM KnowledgeArticleVersion
                WHERE Id IN :kavIds
            ]
        );

        for (RecommendationItem item : items) {
            if (String.isBlank(item.sourceRecordId) || !item.sourceRecordId.startsWith('ka0')) {
                continue;
            }
            Id itemId;
            try {
                itemId = (Id) item.sourceRecordId;
            } catch (Exception ignored) {
                continue;
            }
            if (kavById.containsKey(itemId)) {
                item.articleTitle = kavById.get(itemId).Title;
            }
        }
    }

    private static String readString(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key) || source.get(key) == null) {
            return null;
        }
        String value = String.valueOf(source.get(key));
        return String.isNotBlank(value) ? value : null;
    }
}
