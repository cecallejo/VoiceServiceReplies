String voiceCallId = '0LQHp000003O1JJOA0';

ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
input.isPreview = false;
input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
input.additionalConfig.numGenerations = 1;
input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
input.additionalConfig.temperature = 0.0;

Map<String, String> jsonType = new Map<String, String>{ 'type' => 'json_object' };
ConnectApi.WrappedValue responseFormat = new ConnectApi.WrappedValue();
responseFormat.value = jsonType;
input.additionalConfig.additionalParameters = new Map<String, ConnectApi.WrappedValue>{
    'response_format' => responseFormat
};

Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
Map<String, String> voiceMap = new Map<String, String>{ 'id' => voiceCallId };
ConnectApi.WrappedValue wrappedVoice = new ConnectApi.WrappedValue();
wrappedVoice.value = voiceMap;
valueMap.put('Input:VoiceCall', wrappedVoice);
input.inputParams = valueMap;

try {
    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation grounded =
        ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Draft_Grounded_Service_Reply_Voice', input);
    System.debug('GROUNDED OK => ' + grounded.generations[0].text);
} catch (Exception e) {
    System.debug('GROUNDED ERROR => ' + e.getMessage());
}

try {
    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation context =
        ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Draft_Context_Service_Reply_Voice', input);
    System.debug('CONTEXT OK => ' + context.generations[0].text);
} catch (Exception e) {
    System.debug('CONTEXT ERROR => ' + e.getMessage());
}
