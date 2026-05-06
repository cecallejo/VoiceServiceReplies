Id voiceCallId = '0LQHp000003O1JJOA0';

GroundedRepliesVoiceController.RecommendationResponse res =
    GroundedRepliesVoiceController.generateReplies(
        voiceCallId,
        'Get_Voice_Call_Transcript',
        'Voice_Grounded_Replies_Bridge'
    );

System.debug('SUCCESS => ' + res.success);
System.debug('ERROR => ' + res.errorMessage);
System.debug('TRANSCRIPT PREVIEW => ' + (res.transcript == null ? null : res.transcript.substring(0, Math.min(200, res.transcript.length()))));
System.debug('RAW RESPONSE => ' + res.rawPromptResponse);
System.debug('RECOMMENDATIONS SIZE => ' + (res.recommendations == null ? 0 : res.recommendations.size()));

if (res.recommendations != null) {
    for (GroundedRepliesVoiceController.RecommendationItem item : res.recommendations) {
        System.debug('ITEM => ' + item.text + ' | sourceRecordId=' + item.sourceRecordId + ' | dataSourceObject=' + item.dataSourceObject);
    }
}

if (res.transcript != null) {
    ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
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

    ConnectApi.WrappedValue transcriptParam = new ConnectApi.WrappedValue();
    transcriptParam.value = res.transcript;
    promptInput.inputParams = new Map<String, ConnectApi.WrappedValue>{
        'Input:Transcript' => transcriptParam
    };

    try {
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation directResp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                'Grounded_Service_Reply_Voice_Monitor',
                promptInput
            );
        System.debug('DIRECT PROMPT OK => ' + directResp.generations[0].text);
    } catch (Exception e) {
        System.debug('DIRECT PROMPT ERROR => ' + e.getMessage());
    }
}
