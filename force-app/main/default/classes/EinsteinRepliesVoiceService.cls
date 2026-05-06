public with sharing class EinsteinRepliesVoiceService {
    private static final String REGISTERED_APPLICATION_NAME = 'PromptTemplateGenerationsInvocable';

    public class SuggestionItem {
        @AuraEnabled public String text;
        @AuraEnabled public String source;
        @AuraEnabled public String articleTitle;
        @AuraEnabled public String articleId;
        @AuraEnabled public String dataSourceObject;
    }

    public class SuggestionsResponse {
        @AuraEnabled public List<SuggestionItem> groundedRecommendations;
        @AuraEnabled public List<SuggestionItem> contextRecommendations;
        @AuraEnabled public String errorMessage;
    }

    @AuraEnabled
    public static SuggestionsResponse getSuggestions(
        String voiceCallId,
        String groundedPromptTemplate,
        String contextPromptTemplate
    ) {
        SuggestionsResponse response = new SuggestionsResponse();
        response.groundedRecommendations = new List<SuggestionItem>();
        response.contextRecommendations = new List<SuggestionItem>();
        List<String> errors = new List<String>();

        try {
            validateInputs(voiceCallId, groundedPromptTemplate, contextPromptTemplate);

            if (String.isNotBlank(groundedPromptTemplate)) {
                try {
                    List<SuggestionItem> grounded = invokeTemplate(
                        groundedPromptTemplate,
                        voiceCallId,
                        'grounded'
                    );
                    response.groundedRecommendations.addAll(limitSuggestions(grounded, 2));
                } catch (Exception groundedException) {
                    errors.add('Grounded prompt error: ' + groundedException.getMessage());
                }
            }

            if (String.isNotBlank(contextPromptTemplate)) {
                try {
                    List<SuggestionItem> contextual = invokeTemplate(
                        contextPromptTemplate,
                        voiceCallId,
                        'context'
                    );
                    response.contextRecommendations.addAll(limitSuggestions(contextual, 1));
                } catch (Exception contextException) {
                    errors.add('Context prompt error: ' + contextException.getMessage());
                }
            }

            if (!errors.isEmpty()) {
                response.errorMessage = String.join(errors, ' | ');
            }
        } catch (Exception e) {
            response.errorMessage = e.getMessage();
        }

        return response;
    }

    private static void validateInputs(
        String voiceCallId,
        String groundedPromptTemplate,
        String contextPromptTemplate
    ) {
        if (String.isBlank(voiceCallId)) {
            throw new AuraHandledException('VoiceCall Id is required.');
        }

        if (String.isBlank(groundedPromptTemplate) && String.isBlank(contextPromptTemplate)) {
            throw new AuraHandledException(
                'Configure at least one prompt template: grounded or context.'
            );
        }
    }

    private static List<SuggestionItem> invokeTemplate(
        String templateApiName,
        String voiceCallId,
        String sourceType
    ) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.numGenerations = 1;
        input.additionalConfig.applicationName = REGISTERED_APPLICATION_NAME;
        input.additionalConfig.temperature = 0.0;

        Map<String, String> jsonType = new Map<String, String>{ 'type' => 'json_object' };
        ConnectApi.WrappedValue responseFormat = new ConnectApi.WrappedValue();
        responseFormat.value = jsonType;
        input.additionalConfig.additionalParameters = new Map<String, ConnectApi.WrappedValue>{
            'response_format' => responseFormat
        };

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        Map<String, String> voiceCallMap = new Map<String, String>{ 'id' => voiceCallId };
        ConnectApi.WrappedValue voiceCallValue = new ConnectApi.WrappedValue();
        voiceCallValue.value = voiceCallMap;
        inputParams.put('Input:VoiceCall', voiceCallValue);
        input.inputParams = inputParams;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generation =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateApiName, input);

        if (generation == null || generation.generations == null || generation.generations.isEmpty()) {
            return new List<SuggestionItem>();
        }

        String rawText = generation.generations[0].text;
        return parseSuggestions(rawText, sourceType);
    }

    private static List<SuggestionItem> parseSuggestions(String rawText, String sourceType) {
        List<SuggestionItem> items = new List<SuggestionItem>();
        if (String.isBlank(rawText)) {
            return items;
        }

        Object parsed = JSON.deserializeUntyped(rawText);
        if (!(parsed instanceof Map<String, Object>)) {
            return fallbackToSingleSuggestion(rawText, sourceType);
        }

        Map<String, Object> root = (Map<String, Object>) parsed;
        List<Object> rows = extractRows(root);

        if (rows.isEmpty()) {
            return fallbackToSingleSuggestion(rawText, sourceType);
        }

        for (Object row : rows) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> mappedRow = (Map<String, Object>) row;
            SuggestionItem item = new SuggestionItem();
            item.source = sourceType;
            item.text = readFirstNonBlank(
                mappedRow,
                new List<String>{ 'text', 'recommendation', 'reply', 'answer', 'message', 'content', 'response' }
            );
            item.articleTitle = readFirstNonBlank(
                mappedRow,
                new List<String>{ 'articleTitle', 'knowledgeTitle', 'title' }
            );
            item.articleId = readFirstNonBlank(
                mappedRow,
                new List<String>{ 'articleId', 'knowledgeArticleId', 'knowledgeId' }
            );

            // Supports grounded payload with nested source object:
            // { responses: [ { response: "...", source: { sourceRecordId: "..." } } ] }
            if (String.isBlank(item.articleId) && mappedRow.containsKey('source')) {
                Object sourceObj = mappedRow.get('source');
                if (sourceObj instanceof Map<String, Object>) {
                    Map<String, Object> sourceMap = (Map<String, Object>) sourceObj;
                    item.articleId = readFirstNonBlank(
                        sourceMap,
                        new List<String>{ 'sourceRecordId', 'articleId', 'knowledgeArticleId', 'knowledgeId' }
                    );
                    item.dataSourceObject = readFirstNonBlank(
                        sourceMap,
                        new List<String>{ 'dataSourceObject' }
                    );
                }
            }

            if (String.isNotBlank(item.text)) {
                items.add(item);
            }
        }

        if (items.isEmpty()) {
            return fallbackToSingleSuggestion(rawText, sourceType);
        }

        return items;
    }

    private static List<Object> extractRows(Map<String, Object> root) {
        List<String> candidates = new List<String>{
            'recommendations',
            'groundedRecommendations',
            'contextRecommendations',
            'responses',
            'items'
        };
        for (String key : candidates) {
            if (root.containsKey(key) && root.get(key) instanceof List<Object>) {
                return (List<Object>) root.get(key);
            }
        }
        return new List<Object>();
    }

    private static String readFirstNonBlank(Map<String, Object> source, List<String> keys) {
        for (String key : keys) {
            if (source.containsKey(key) && source.get(key) != null) {
                String value = String.valueOf(source.get(key));
                if (String.isNotBlank(value)) {
                    return value.trim();
                }
            }
        }
        return null;
    }

    private static List<SuggestionItem> fallbackToSingleSuggestion(String text, String sourceType) {
        SuggestionItem fallback = new SuggestionItem();
        fallback.text = text;
        fallback.source = sourceType;
        return new List<SuggestionItem>{ fallback };
    }

    private static List<SuggestionItem> limitSuggestions(List<SuggestionItem> source, Integer maxItems) {
        List<SuggestionItem> limited = new List<SuggestionItem>();
        if (source == null || source.isEmpty() || maxItems <= 0) {
            return limited;
        }
        Integer boundary = Math.min(source.size(), maxItems);
        for (Integer i = 0; i < boundary; i++) {
            limited.add(source[i]);
        }
        return limited;
    }
}
