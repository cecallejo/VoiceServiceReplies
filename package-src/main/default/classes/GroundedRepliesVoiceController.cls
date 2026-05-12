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

    public class SentimentResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String rawPromptResponse;
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

            RecommendationResponse byTranscript = generateRepliesFromTranscript(
                voiceCallId,
                transcript,
                groundingFlowName
            );
            result.rawPromptResponse = byTranscript.rawPromptResponse;
            result.recommendations = byTranscript.recommendations;
            result.success = byTranscript.success;
            result.errorMessage = byTranscript.errorMessage;
        } catch (Exception e) {
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    @AuraEnabled
    public static RecommendationResponse generateRepliesFromTranscript(
        Id voiceCallId,
        String transcript,
        String groundingFlowName
    ) {
        RecommendationResponse result = new RecommendationResponse();
        result.success = false;
        result.recommendations = new List<RecommendationItem>();
        result.transcript = transcript;

        try {
            if (voiceCallId == null) {
                throw new AuraHandledException('VoiceCall Id is required.');
            }
            if (String.isBlank(transcript)) {
                throw new AuraHandledException('Transcript is required.');
            }
            if (String.isBlank(groundingFlowName)) {
                throw new AuraHandledException('Grounding Flow Name is required.');
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

    @AuraEnabled
    public static SentimentResponse analyzeSentimentFromTranscript(
        Id voiceCallId,
        String transcript,
        String sentimentPromptName
    ) {
        SentimentResponse result = new SentimentResponse();
        result.success = false;

        try {
            if (voiceCallId == null) {
                throw new AuraHandledException('VoiceCall Id is required.');
            }
            if (String.isBlank(transcript)) {
                throw new AuraHandledException('Transcript is required.');
            }
            if (String.isBlank(sentimentPromptName)) {
                throw new AuraHandledException('Sentiment Prompt Name is required.');
            }

            String promptResponse = runSentimentPrompt(voiceCallId, transcript, sentimentPromptName);
            result.rawPromptResponse = promptResponse;
            result.sentiment = parseSentiment(promptResponse);
            result.success = String.isNotBlank(result.sentiment);
            if (!result.success) {
                result.errorMessage = 'Could not identify sentiment from prompt response.';
            }
        } catch (Exception e) {
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    @AuraEnabled
    public static String fetchTranscript(Id voiceCallId, String transcriptFlowName) {
        if (voiceCallId == null) {
            throw new AuraHandledException('VoiceCall Id is required.');
        }
        if (String.isBlank(transcriptFlowName)) {
            throw new AuraHandledException('Transcript Flow Name is required.');
        }
        return runTranscriptFlow(voiceCallId, transcriptFlowName);
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

    private static String runSentimentPrompt(Id voiceCallId, String transcript, String promptName) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.isPreview = false;
        promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        promptInput.additionalConfig.numGenerations = 1;
        promptInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        promptInput.additionalConfig.temperature = 0.0;

        Map<String, String> jsonType = new Map<String, String>{ 'type' => 'json_object' };
        ConnectApi.WrappedValue responseFormat = new ConnectApi.WrappedValue();
        responseFormat.value = jsonType;
        promptInput.additionalConfig.additionalParameters = new Map<String, ConnectApi.WrappedValue>{
            'response_format' => responseFormat
        };

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        Map<String, String> voiceCallMap = new Map<String, String>{ 'id' => (String) voiceCallId };
        ConnectApi.WrappedValue voiceCallValue = new ConnectApi.WrappedValue();
        voiceCallValue.value = voiceCallMap;
        inputParams.put('Input:VoiceCall', voiceCallValue);

        ConnectApi.WrappedValue transcriptValue = new ConnectApi.WrappedValue();
        transcriptValue.value = transcript;
        inputParams.put('Input:Transcript', transcriptValue);
        inputParams.put('transcript', transcriptValue);
        inputParams.put('Transcript', transcriptValue);

        promptInput.inputParams = inputParams;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(promptName, promptInput);
        if (output == null || output.generations == null || output.generations.isEmpty()) {
            return null;
        }

        return output.generations[0].text;
    }

    @TestVisible
    private static List<RecommendationItem> parseRecommendations(String rawResponse) {
        List<RecommendationItem> output = new List<RecommendationItem>();
        if (String.isBlank(rawResponse)) {
            return output;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(rawResponse);
        } catch (Exception ignored) {
            RecommendationItem fallback = new RecommendationItem();
            fallback.text = rawResponse;
            output.add(fallback);
            return output;
        }
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

        Map<Id, String> kavById = new Map<Id, String>();
        try {
            for (SObject row : Database.query(
                'SELECT Id, Title FROM KnowledgeArticleVersion WHERE Id IN :kavIds'
            )) {
                Id rowId = (Id) row.get('Id');
                String title = (String) row.get('Title');
                if (rowId != null && String.isNotBlank(title)) {
                    kavById.put(rowId, title);
                }
            }
        } catch (Exception ignored) {
            return;
        }

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
                item.articleTitle = kavById.get(itemId);
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

    private static String parseSentiment(String rawResponse) {
        if (String.isBlank(rawResponse)) {
            return null;
        }

        String normalized = normalizeSentiment(rawResponse);
        if (normalized != null) {
            return normalized;
        }

        try {
            Object parsed = JSON.deserializeUntyped(rawResponse);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> root = (Map<String, Object>) parsed;
                List<String> candidateKeys = new List<String>{
                    'sentiment',
                    'Sentiment',
                    'sentimento',
                    'Sentimento',
                    'classification',
                    'Classificacao',
                    'classificacao',
                    'label',
                    'Label'
                };
                for (String key : candidateKeys) {
                    if (!root.containsKey(key) || root.get(key) == null) {
                        continue;
                    }
                    String parsedValue = normalizeSentiment(String.valueOf(root.get(key)));
                    if (parsedValue != null) {
                        return parsedValue;
                    }
                }
            }
        } catch (Exception ignored) {
            // Ignore parsing errors and return null.
        }

        return null;
    }

    private static String normalizeSentiment(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String lowered = value.toLowerCase();
        if (lowered.contains('positiv')) {
            return 'positivo';
        }
        if (lowered.contains('negativ')) {
            return 'negativo';
        }
        if (lowered.contains('neutr')) {
            return 'neutro';
        }
        return null;
    }
}
