public class qblmrt_SentimentAnalysis {
    @AuraEnabled
    public static String invokePrompt(String messagingSessionId) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput promptGenerationsInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptGenerationsInput.isPreview = false;
        promptGenerationsInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        promptGenerationsInput.additionalConfig.numGenerations = 1;
        promptGenerationsInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        promptGenerationsInput.additionalConfig.temperature = 0.0;
        Map<String, String> jsonType = new Map<String, String>{
            'type' => 'json_object'
        };
        ConnectApi.WrappedValue responseFormatProperty = new ConnectApi.WrappedValue();
        responseFormatProperty.value = jsonType;
        promptGenerationsInput.additionalConfig.additionalParameters = new Map<String, ConnectApi.WrappedValue>{
            'response_format' => responseFormatProperty
        };
            
        // Build input map
        Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
        Map<String, String> messagingSessionMap = new Map<String, String>();
        messagingSessionMap.put('id', messagingSessionId);
        ConnectApi.WrappedValue inputDetailWrappedValue = new ConnectApi.WrappedValue();
        inputDetailWrappedValue.value = messagingSessionMap;
        valueMap.put('Input:MessagingSession', inputDetailWrappedValue);
        promptGenerationsInput.inputParams = valueMap;

        System.debug(promptGenerationsInput);

        //execute
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput = 
        ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('qblmrt_Customer_Sentiment_for_Messaging', promptGenerationsInput);
        ConnectApi.EinsteinLLMGenerationItemOutput response = generationsOutput.generations[0];

        System.debug(response.text);

        return response.text;
    }
}