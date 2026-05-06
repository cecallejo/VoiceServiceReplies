/**
 * @description Controller for the Checklist Monitor LWC.
 *              Handles checklist retrieval, transcript evaluation via Agentforce,
 *              template management, conditional items, and manual status updates.
 *              Supports both VoiceCall and MessagingSession records.
 * @version 1.3
 */
public with sharing class VoiceChecklistController {
    
    // Review Status picklist values
    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_COMPLETED_AI = 'Completed (AI)';
    private static final String STATUS_COMPLETED_MANUAL = 'Completed (Manual)';
    private static final String STATUS_NOT_APPLICABLE = 'Not Applicable';
    private static final String STATUS_MISSED = 'Missed';
    
    /**
     * @description Wrapper for checklist header info
     */
    public class ChecklistInfo {
        @AuraEnabled public Id checklistId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Id voiceCallId { get; set; }
        @AuraEnabled public Id messagingSessionId { get; set; }
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public String templateName { get; set; }
    }
    
    /**
     * @description Wrapper for checklist data returned to LWC
     */
    public class ChecklistWrapper {
        @AuraEnabled public ChecklistInfo checklist { get; set; }
        @AuraEnabled public List<ChecklistItemWrapper> items { get; set; }
        @AuraEnabled public Integer totalItems { get; set; }
        @AuraEnabled public Integer completedItems { get; set; }
        @AuraEnabled public Integer notApplicableItems { get; set; }
        @AuraEnabled public Integer missedItems { get; set; }
        @AuraEnabled public Decimal completionPercentage { get; set; }
        
        public ChecklistWrapper() {
            this.items = new List<ChecklistItemWrapper>();
            this.totalItems = 0;
            this.completedItems = 0;
            this.notApplicableItems = 0;
            this.missedItems = 0;
            this.completionPercentage = 0;
        }
    }
    
    /**
     * @description Wrapper for individual checklist items with hierarchy info
     */
    public class ChecklistItemWrapper {
        @AuraEnabled public Id itemId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String checklistItemDescription { get; set; }
        @AuraEnabled public Decimal itemSequence { get; set; }
        @AuraEnabled public Integer checklistLevel { get; set; }
        @AuraEnabled public String userInstructions { get; set; }
        @AuraEnabled public String itemStatus { get; set; }
        @AuraEnabled public String reviewSource { get; set; }
        @AuraEnabled public Datetime reviewedAt { get; set; }
        @AuraEnabled public String reviewedBy { get; set; }
        @AuraEnabled public Boolean isChild { get; set; }
        @AuraEnabled public Boolean hasChildren { get; set; }
        @AuraEnabled public Boolean isConditional { get; set; }
        @AuraEnabled public String conditionDescription { get; set; }
        @AuraEnabled public String matchingHints { get; set; }
        // Quick Insert/Send properties for Messaging Sessions
        @AuraEnabled public String quickInsertText { get; set; }
        @AuraEnabled public Boolean enableQuickInsert { get; set; }
        @AuraEnabled public Boolean enableQuickSend { get; set; }
    }
    
    /**
     * @description Wrapper for template data returned to LWC
     */
    public class TemplateWrapper {
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String version { get; set; }
        @AuraEnabled public Integer itemCount { get; set; }
    }
    
    /**
     * @description Wrapper for evaluation response
     */
    public class EvaluationResponse {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public List<String> itemsCompleted { get; set; }
        @AuraEnabled public ChecklistWrapper updatedChecklist { get; set; }
        @AuraEnabled public String error { get; set; }
        
        public EvaluationResponse() {
            this.isSuccess = false;
            this.itemsCompleted = new List<String>();
        }
    }
    
    /**
     * @description Wrapper for verification response
     */
    public class VerificationResponse {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public List<String> itemsVerified { get; set; }
        @AuraEnabled public List<String> itemsNeedingReview { get; set; }
        @AuraEnabled public List<String> itemsIncomplete { get; set; }
        @AuraEnabled public List<String> itemsNotApplicable { get; set; }
        @AuraEnabled public List<String> itemsMissed { get; set; }
        @AuraEnabled public ChecklistWrapper updatedChecklist { get; set; }
        @AuraEnabled public String error { get; set; }
        
        public VerificationResponse() {
            this.isSuccess = false;
            this.itemsVerified = new List<String>();
            this.itemsNeedingReview = new List<String>();
            this.itemsIncomplete = new List<String>();
            this.itemsNotApplicable = new List<String>();
            this.itemsMissed = new List<String>();
        }
    }
    
    // ===== Template Methods =====
    
    /**
     * @description Get all active templates for the template picker
     * @return List of TemplateWrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getActiveTemplates() {
        List<TemplateWrapper> templates = new List<TemplateWrapper>();
        
        List<Voice_Checklist_Template__c> templateRecords = [
            SELECT Id, Name, Description__c, Version__c,
                   (SELECT Id FROM Template_Items__r)
            FROM Voice_Checklist_Template__c
            WHERE Is_Active__c = true
            ORDER BY Name
        ];
        
        for (Voice_Checklist_Template__c t : templateRecords) {
            TemplateWrapper tw = new TemplateWrapper();
            tw.templateId = t.Id;
            tw.name = t.Name;
            tw.description = t.Description__c;
            tw.version = t.Version__c;
            tw.itemCount = t.Template_Items__r.size();
            templates.add(tw);
        }
        
        return templates;
    }
    
    /**
     * @description Select a template for a session (VoiceCall or MessagingSession)
     * @param sessionId The VoiceCall or MessagingSession record Id
     * @param templateId The template to select
     * @return True if successful
     */
    @AuraEnabled
    public static Boolean selectTemplateForSession(Id sessionId, Id templateId) {
        try {
            String objectType = sessionId.getSobjectType().getDescribe().getName();
            
            if (objectType == 'VoiceCall') {
                VoiceCall vc = new VoiceCall(
                    Id = sessionId,
                    Selected_Checklist_Template__c = templateId
                );
                update vc;
            } else if (objectType == 'MessagingSession') {
                MessagingSession ms = new MessagingSession(
                    Id = sessionId,
                    Selected_Checklist_Template__c = templateId
                );
                update ms;
            } else {
                throw new AuraHandledException('Unsupported object type: ' + objectType);
            }
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'VoiceChecklistController.selectTemplateForSession: ' + e.getMessage());
            throw new AuraHandledException('Failed to select template: ' + e.getMessage());
        }
    }
    
    /**
     * @description Legacy method for backward compatibility
     */
    @AuraEnabled
    public static Boolean selectTemplate(Id voiceCallId, Id templateId) {
        return selectTemplateForSession(voiceCallId, templateId);
    }
    
    // ===== Unified Checklist Retrieval =====
    
    /**
     * @description Get checklist for either VoiceCall or MessagingSession
     * @param parentRecordId Either VoiceCall ID or MessagingSession ID
     * @return ChecklistWrapper with items
     */
    @AuraEnabled
    public static ChecklistWrapper getChecklistForParentRecord(Id parentRecordId) {
        if (parentRecordId == null) {
            return new ChecklistWrapper();
        }
        
        String objectType = parentRecordId.getSobjectType().getDescribe().getName();
        
        if (objectType == 'VoiceCall') {
            return getChecklistForVoiceCallUncached(parentRecordId);
        } else if (objectType == 'MessagingSession') {
            return getChecklistForMessagingSessionUncached(parentRecordId);
        }
        
        return new ChecklistWrapper();
    }
    
    /**
     * @description Get checklist and items for a Voice Call (cached)
     */
    @AuraEnabled(cacheable=true)
    public static ChecklistWrapper getChecklistForVoiceCall(Id voiceCallId) {
        return getChecklistForVoiceCallUncached(voiceCallId);
    }
    
    /**
     * @description Get checklist and items for a Voice Call (uncached)
     */
    @AuraEnabled
    public static ChecklistWrapper getChecklistForVoiceCallUncached(Id voiceCallId) {
        ChecklistWrapper wrapper = new ChecklistWrapper();
        
        if (voiceCallId == null) {
            return wrapper;
        }
        
        List<Voice_Checklist__c> checklists = [
            SELECT Id, Name, Status__c, Voice_Call__c, Template__c, Template__r.Name
            FROM Voice_Checklist__c
            WHERE Voice_Call__c = :voiceCallId
            LIMIT 1
        ];
        
        if (checklists.isEmpty()) {
            return wrapper;
        }
        
        Voice_Checklist__c checklistRecord = checklists[0];
        
        ChecklistInfo info = new ChecklistInfo();
        info.checklistId = checklistRecord.Id;
        info.name = checklistRecord.Name;
        info.status = checklistRecord.Status__c;
        info.voiceCallId = checklistRecord.Voice_Call__c;
        info.templateId = checklistRecord.Template__c;
        info.templateName = checklistRecord.Template__r.Name;
        wrapper.checklist = info;
        
        return buildChecklistItems(wrapper, checklistRecord.Id);
    }
    
    /**
     * @description Get checklist and items for a Messaging Session (uncached)
     */
    @AuraEnabled
    public static ChecklistWrapper getChecklistForMessagingSessionUncached(Id messagingSessionId) {
        ChecklistWrapper wrapper = new ChecklistWrapper();
        
        if (messagingSessionId == null) {
            return wrapper;
        }
        
        List<Voice_Checklist__c> checklists = [
            SELECT Id, Name, Status__c, Messaging_Session__c, Template__c, Template__r.Name
            FROM Voice_Checklist__c
            WHERE Messaging_Session__c = :messagingSessionId
            LIMIT 1
        ];
        
        if (checklists.isEmpty()) {
            return wrapper;
        }
        
        Voice_Checklist__c checklistRecord = checklists[0];
        
        ChecklistInfo info = new ChecklistInfo();
        info.checklistId = checklistRecord.Id;
        info.name = checklistRecord.Name;
        info.status = checklistRecord.Status__c;
        info.messagingSessionId = checklistRecord.Messaging_Session__c;
        info.templateId = checklistRecord.Template__c;
        info.templateName = checklistRecord.Template__r.Name;
        wrapper.checklist = info;
        
        return buildChecklistItems(wrapper, checklistRecord.Id);
    }
    
    /**
     * @description Build checklist items for a wrapper
     */
    private static ChecklistWrapper buildChecklistItems(ChecklistWrapper wrapper, Id checklistId) {
        List<Voice_Checklist_Item__c> items = [
            SELECT Id, Title__c, Checklist_Item_Description__c, Item_Sequence__c,
                   Checklist_Level__c, User_Instructions__c, Item_Status__c,
                   Review_Source__c, Reviewed_At__c, Reviewed_By__c,
                   Is_Conditional__c, Condition_Description__c, Matching_Hints__c,
                   Quick_Insert_Text__c, Enable_Quick_Insert__c, Enable_Quick_Send__c
            FROM Voice_Checklist_Item__c
            WHERE Voice_Checklist__c = :checklistId
            ORDER BY Item_Sequence__c ASC
        ];
        
        Set<Decimal> parentSequences = new Set<Decimal>();
        for (Voice_Checklist_Item__c item : items) {
            if (item.Checklist_Level__c == 1) {
                parentSequences.add(item.Item_Sequence__c);
            }
        }
        
        Integer totalCount = 0;
        Integer completedCount = 0;
        Integer naCount = 0;
        Integer missedCount = 0;
        
        for (Voice_Checklist_Item__c item : items) {
            ChecklistItemWrapper itemWrapper = new ChecklistItemWrapper();
            itemWrapper.itemId = item.Id;
            itemWrapper.title = item.Title__c;
            itemWrapper.checklistItemDescription = item.Checklist_Item_Description__c;
            itemWrapper.itemSequence = item.Item_Sequence__c;
            itemWrapper.checklistLevel = item.Checklist_Level__c != null ? item.Checklist_Level__c.intValue() : 1;
            itemWrapper.userInstructions = item.User_Instructions__c;
            itemWrapper.itemStatus = item.Item_Status__c;
            itemWrapper.reviewSource = item.Review_Source__c;
            itemWrapper.reviewedAt = item.Reviewed_At__c;
            itemWrapper.reviewedBy = item.Reviewed_By__c;
            itemWrapper.isChild = item.Checklist_Level__c == 2;
            itemWrapper.isConditional = item.Is_Conditional__c == true;
            itemWrapper.conditionDescription = item.Condition_Description__c;
            itemWrapper.matchingHints = item.Matching_Hints__c;
            // Quick Insert/Send fields
            itemWrapper.quickInsertText = item.Quick_Insert_Text__c;
            itemWrapper.enableQuickInsert = item.Enable_Quick_Insert__c == true;
            itemWrapper.enableQuickSend = item.Enable_Quick_Send__c == true;
            
            if (item.Checklist_Level__c == 1) {
                Decimal seq = item.Item_Sequence__c;
                itemWrapper.hasChildren = false;
                for (Voice_Checklist_Item__c child : items) {
                    if (child.Checklist_Level__c == 2 && 
                        child.Item_Sequence__c > seq && 
                        child.Item_Sequence__c < seq + 1) {
                        itemWrapper.hasChildren = true;
                        break;
                    }
                }
            }
            
            totalCount++;
            String status = item.Item_Status__c;
            if (status == STATUS_COMPLETED_AI || status == STATUS_COMPLETED_MANUAL) {
                completedCount++;
            } else if (status == STATUS_NOT_APPLICABLE) {
                naCount++;
            } else if (status == STATUS_MISSED) {
                missedCount++;
            }
            
            wrapper.items.add(itemWrapper);
        }
        
        wrapper.totalItems = totalCount;
        wrapper.completedItems = completedCount;
        wrapper.notApplicableItems = naCount;
        wrapper.missedItems = missedCount;
        
        Integer applicableItems = totalCount - naCount;
        wrapper.completionPercentage = applicableItems > 0 ? 
            ((Decimal)completedCount / applicableItems * 100).setScale(0) : 0;
        
        return wrapper;
    }
    
    // ===== Manual Update Methods =====
    
    /**
     * @description Update item status (manual check/uncheck by user)
     */
    @AuraEnabled
    public static ChecklistWrapper updateItemStatus(Id itemId, String newStatus) {
        try {
            Voice_Checklist_Item__c item = [
                SELECT Id, Voice_Checklist__c, Voice_Checklist__r.Voice_Call__c, Voice_Checklist__r.Messaging_Session__c
                FROM Voice_Checklist_Item__c
                WHERE Id = :itemId
                LIMIT 1
            ];
            
            item.Item_Status__c = newStatus;
            
            if (newStatus == STATUS_COMPLETED_MANUAL) {
                item.Review_Source__c = 'Manual Override';
                item.Reviewed_At__c = Datetime.now();
                item.Reviewed_By__c = UserInfo.getName();
            } else if (newStatus == STATUS_PENDING) {
                item.Review_Source__c = null;
                item.Reviewed_At__c = null;
                item.Reviewed_By__c = null;
            }
            
            update item;
            
            // Return updated checklist based on parent type
            if (item.Voice_Checklist__r.Voice_Call__c != null) {
                return getChecklistForVoiceCallUncached(item.Voice_Checklist__r.Voice_Call__c);
            } else if (item.Voice_Checklist__r.Messaging_Session__c != null) {
                return getChecklistForMessagingSessionUncached(item.Voice_Checklist__r.Messaging_Session__c);
            }
            
            return new ChecklistWrapper();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'VoiceChecklistController.updateItemStatus: ' + e.getMessage());
            throw new AuraHandledException('Failed to update item: ' + e.getMessage());
        }
    }
    
    // ===== Real-Time Evaluation Methods =====
    
/**
     * @description Evaluate transcript batch against unchecked items
     * Alterado para considerar a transcrição completa via Flow
     */
    @AuraEnabled
    public static EvaluationResponse evaluateTranscript(Id parentRecordId, String transcript, String evaluatorFlowName) {
        EvaluationResponse response = new EvaluationResponse();
        
        try {
            // Buscamos a transcrição completa via Flow, ignorando o trecho parcial recebido por parâmetro
            // O nome do flow de transcrição aqui assume o padrão do sistema ou pode ser passado dinamicamente
            // Para manter compatibilidade, tentaremos buscar a transcrição completa:
            String fullTranscript = getTranscriptFromFlow(parentRecordId, 'Get_Voice_Call_Transcript'); 

            // Fallback: se o flow de transcrição falhar ou não retornar nada, usamos o trecho enviado
            if (String.isBlank(fullTranscript)) {
                fullTranscript = transcript;
            }

            if (String.isBlank(fullTranscript)) {
                response.error = 'No transcript provided';
                return response;
            }
            
            ChecklistWrapper currentChecklist = getChecklistForParentRecord(parentRecordId);
            
            if (currentChecklist.checklist == null) {
                response.error = 'No Checklist found for this record.';
                return response;
            }
            
            List<Map<String, String>> pendingItems = new List<Map<String, String>>();
            Map<String, Id> itemTitleToId = new Map<String, Id>();
            
            for (ChecklistItemWrapper item : currentChecklist.items) {
                itemTitleToId.put(item.title, item.itemId);
                
                if (item.itemStatus == null || item.itemStatus == STATUS_PENDING) {
                    Map<String, String> itemInfo = new Map<String, String>{
                        'title' => item.title,
                        'description' => item.checklistItemDescription,
                        'level' => String.valueOf(item.checklistLevel),
                        'isConditional' => String.valueOf(item.isConditional),
                        'condition' => item.conditionDescription != null ? item.conditionDescription : '',
                        'hints' => item.matchingHints != null ? item.matchingHints : ''
                    };
                    pendingItems.add(itemInfo);
                }
            }
            
            if (pendingItems.isEmpty()) {
                response.isSuccess = true;
                response.updatedChecklist = currentChecklist;
                return response;
            }
            
            // Agora enviamos o fullTranscript consolidado para o prompt
            String userMessage = buildEvaluationPrompt(fullTranscript, pendingItems);
            
            Map<String, Object> flowInputs = new Map<String, Object>{
                'userMessage' => userMessage
            };
            
            Flow.Interview flowInterview = Flow.Interview.createInterview(evaluatorFlowName, flowInputs);
            flowInterview.start();
            
            String aiResponse = (String) flowInterview.getVariableValue('agentResponse');
            
            if (String.isBlank(aiResponse)) {
                response.error = 'No response from AI evaluator';
                return response;
            }
            
            List<String> discussedItems = parseAIResponse(aiResponse);
            List<Voice_Checklist_Item__c> itemsToUpdate = new List<Voice_Checklist_Item__c>();
            
            for (String itemTitle : discussedItems) {
                Id itemId = itemTitleToId.get(itemTitle);
                if (itemId != null) {
                    itemsToUpdate.add(new Voice_Checklist_Item__c(
                        Id = itemId,
                        Item_Status__c = STATUS_COMPLETED_AI,
                        Review_Source__c = 'Agentforce Auto',
                        Reviewed_At__c = Datetime.now(),
                        Reviewed_By__c = 'Agentforce'
                    ));
                    response.itemsCompleted.add(itemTitle);
                }
            }
            
            if (!itemsToUpdate.isEmpty()) {
                update itemsToUpdate;
            }
            
            response.isSuccess = true;
            response.updatedChecklist = getChecklistForParentRecord(parentRecordId);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'VoiceChecklistController.evaluateTranscript: ' + e.getMessage() + '\n' + e.getStackTraceString());
            response.error = 'Evaluation error: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * @description Build the evaluation prompt for real-time analysis
     */
    private static String buildEvaluationPrompt(String transcript, List<Map<String, String>> pendingItems) {
        String prompt = 'Analyze this conversation transcript and identify which checklist items were discussed.\n\n';
        prompt += 'TRANSCRIPT:\n' + transcript + '\n\n';
        prompt += 'CHECKLIST ITEMS TO CHECK:\n';
        
        for (Map<String, String> item : pendingItems) {
            prompt += '- ' + item.get('title') + ': ' + item.get('description');
            
            String hints = item.get('hints');
            if (String.isNotBlank(hints)) {
                prompt += ' [HINTS: ' + hints + ']';
            }
            
            if (item.get('isConditional') == 'true' && String.isNotBlank(item.get('condition'))) {
                prompt += ' [CONDITIONAL: ' + item.get('condition') + ']';
            }
            prompt += '\n';
        }
        
        prompt += 'EVALUATION GUIDELINES:\n';
        prompt += '1. BE INCLUSIVE: If the agent addressed the topic in ANY reasonable way, mark it as discussed.\n';
        prompt += '2. Focus on MEANING and INTENT, not exact word matches.\n';
        prompt += '3. Use the HINTS provided with each item to recognize equivalent phrases or actions.\n';
        prompt += 'Return ONLY a JSON object. Use ONLY the item name (text BEFORE the colon), not the description:\n';
        prompt += 'Example: {"itemsDiscussed": ["HIPAA Verification", "Identify Specific Claim"]}\n';
        prompt += 'If no items were discussed, return: {"itemsDiscussed": []}';
        
        return prompt;
    }
    
    /**
     * @description Parse AI response to extract discussed items
     */
    private static List<String> parseAIResponse(String aiResponse) {
        List<String> items = new List<String>();
        
        try {
            Integer startIdx = aiResponse.indexOf('{');
            Integer endIdx = aiResponse.lastIndexOf('}');
            
            if (startIdx >= 0 && endIdx > startIdx) {
                String jsonStr = aiResponse.substring(startIdx, endIdx + 1);
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
                
                if (parsed.containsKey('itemsDiscussed')) {
                    List<Object> discussedList = (List<Object>) parsed.get('itemsDiscussed');
                    for (Object item : discussedList) {
                        items.add(String.valueOf(item));
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'VoiceChecklistController.parseAIResponse: Parse error - ' + e.getMessage());
        }
        
        return items;
    }
    
    // ===== Verification Methods =====
    
    /**
     * @description Verify checklist against full transcript (supports both Voice and Messaging)
     */
    @AuraEnabled
    public static VerificationResponse verifyChecklist(Id parentRecordId, String transcriptFlowName, String evaluatorFlowName, Boolean markMissed) {
        VerificationResponse response = new VerificationResponse();
        
        try {
            // Get the full transcript using the appropriate flow
            String fullTranscript = getTranscriptFromFlow(parentRecordId, transcriptFlowName);
            
            if (String.isBlank(fullTranscript)) {
                response.error = 'No transcript available for this session.';
                return response;
            }
            
            // Get current checklist state
            ChecklistWrapper currentChecklist = getChecklistForParentRecord(parentRecordId);
            
            if (currentChecklist.checklist == null) {
                response.error = 'No Checklist found for this session.';
                return response;
            }
            
            // Categorize items
            List<Map<String, Object>> pendingItems = new List<Map<String, Object>>();
            List<Map<String, Object>> manualItems = new List<Map<String, Object>>();
            Map<String, Id> itemTitleToId = new Map<String, Id>();
            Map<String, ChecklistItemWrapper> itemByTitle = new Map<String, ChecklistItemWrapper>();
            
            for (ChecklistItemWrapper item : currentChecklist.items) {
                itemTitleToId.put(item.title, item.itemId);
                itemByTitle.put(item.title, item);
                
                String status = item.itemStatus;
                
                if (status == null || status == STATUS_PENDING || status == STATUS_MISSED) {
                    Map<String, Object> itemInfo = new Map<String, Object>{
                        'title' => item.title,
                        'description' => item.checklistItemDescription,
                        'level' => item.checklistLevel,
                        'isConditional' => item.isConditional,
                        'condition' => item.conditionDescription,
                        'hints' => item.matchingHints,
                        'sequence' => item.itemSequence
                    };
                    pendingItems.add(itemInfo);
                } else if (status == STATUS_COMPLETED_MANUAL) {
                    Map<String, Object> itemInfo = new Map<String, Object>{
                        'title' => item.title,
                        'description' => item.checklistItemDescription,
                        'level' => item.checklistLevel,
                        'isConditional' => item.isConditional,
                        'condition' => item.conditionDescription,
                        'hints' => item.matchingHints,
                        'sequence' => item.itemSequence
                    };
                    manualItems.add(itemInfo);
                }
            }
            
            // Build verification prompt
            String verificationPrompt = buildVerificationPrompt(fullTranscript, pendingItems, manualItems);
            
            Map<String, Object> flowInputs = new Map<String, Object>{
                'userMessage' => verificationPrompt
            };
            
            Flow.Interview flowInterview = Flow.Interview.createInterview(evaluatorFlowName, flowInputs);
            flowInterview.start();
            
            String aiResponse = (String) flowInterview.getVariableValue('agentResponse');
            
            if (String.isBlank(aiResponse)) {
                response.error = 'No response from AI evaluator';
                return response;
            }
            
            // Parse response
            Map<String, Object> parsedResponse = parseVerificationResponse(aiResponse);
            List<String> discussedItems = (List<String>) parsedResponse.get('discussed');
            List<String> notDiscussedItems = (List<String>) parsedResponse.get('notDiscussed');
            List<String> notApplicableItems = (List<String>) parsedResponse.get('notApplicable');
            
            // Update items
            List<Voice_Checklist_Item__c> itemsToUpdate = new List<Voice_Checklist_Item__c>();
            Set<Id> processedIds = new Set<Id>();
            
            // Mark discussed items as verified
            // First, identify which items AI marked as discussed (parent and child)
            Set<String> discussedItemTitles = new Set<String>(discussedItems);
            
            // Build map of parent sequences to their verified children
            Set<Integer> verifiedChildParentSequences = new Set<Integer>();
            for (ChecklistItemWrapper item : currentChecklist.items) {
                if (item.checklistLevel == 2 && item.itemSequence != null) {
                    // Check if this child was verified
                    if (discussedItemTitles.contains(item.title)) {
                        Integer parentSeq = item.itemSequence.intValue();
                        verifiedChildParentSequences.add(parentSeq);
                    }
                }
            }
            
            // Mark items as verified - but for parents with children, require at least one child verified
            for (String itemTitle : discussedItems) {
                Id itemId = itemTitleToId.get(itemTitle);
                ChecklistItemWrapper itemWrapper = itemByTitle.get(itemTitle);
                
                if (itemId != null && itemWrapper != null) {
                    String currentStatus = itemWrapper.itemStatus;
                    
                    if (currentStatus == null || currentStatus == STATUS_PENDING || currentStatus == STATUS_MISSED || currentStatus == STATUS_COMPLETED_MANUAL) {
                        // Check if this is a parent with children
                        if (itemWrapper.checklistLevel == 1 && itemWrapper.hasChildren) {
                            Integer parentSeq = itemWrapper.itemSequence.intValue();
                            
                            // Parent has children - require at least one child to be verified
                            if (!verifiedChildParentSequences.contains(parentSeq)) {
                                // Parent was discussed but no children were verified - keep parent as pending
                                System.debug(LoggingLevel.INFO, 'VoiceChecklistController.verifyChecklist: Parent item "' + itemTitle + '" was discussed but no children were verified. Keeping parent as pending.');
                                continue; // Skip verifying this parent
                            }
                        }
                        
                        // Parent has no children OR at least one child was verified - verify the item
                        itemsToUpdate.add(new Voice_Checklist_Item__c(
                            Id = itemId,
                            Item_Status__c = STATUS_COMPLETED_AI,
                            Review_Source__c = 'Agentforce Verify',
                            Reviewed_At__c = Datetime.now(),
                            Reviewed_By__c = 'Agentforce'
                        ));
                        processedIds.add(itemId);
                        response.itemsVerified.add(itemTitle);
                    }
                }
            }
            
            // Mark not applicable items - ONLY if they are conditional
            // Safety check: Ignore any non-conditional items that AI incorrectly put in notApplicableItems
            Set<Integer> naParentSequences = new Set<Integer>();
            for (String itemTitle : notApplicableItems) {
                Id itemId = itemTitleToId.get(itemTitle);
                ChecklistItemWrapper itemWrapper = itemByTitle.get(itemTitle);
                
                // Safety check: Only mark as N/A if item is actually conditional
                if (itemWrapper != null && !itemWrapper.isConditional) {
                    System.debug(LoggingLevel.WARN, 'VoiceChecklistController.verifyChecklist: AI incorrectly marked non-conditional item as N/A: ' + itemTitle + '. Moving to notDiscussedItems.');
                    // Move to notDiscussedItems instead
                    if (!notDiscussedItems.contains(itemTitle)) {
                        notDiscussedItems.add(itemTitle);
                    }
                    continue;
                }
                
                if (itemId != null && !processedIds.contains(itemId)) {
                    itemsToUpdate.add(new Voice_Checklist_Item__c(
                        Id = itemId,
                        Item_Status__c = STATUS_NOT_APPLICABLE,
                        Review_Source__c = 'Agentforce Verify',
                        Reviewed_At__c = Datetime.now(),
                        Reviewed_By__c = 'Agentforce'
                    ));
                    processedIds.add(itemId);
                    response.itemsNotApplicable.add(itemTitle);
                    
                    if (itemWrapper != null && itemWrapper.checklistLevel == 1) {
                        naParentSequences.add(itemWrapper.itemSequence.intValue());
                    }
                }
            }
            
            // Cascade N/A to children
            for (ChecklistItemWrapper item : currentChecklist.items) {
                if (item.checklistLevel == 2 && !processedIds.contains(item.itemId)) {
                    Integer parentSeq = item.itemSequence.intValue();
                    if (naParentSequences.contains(parentSeq)) {
                        itemsToUpdate.add(new Voice_Checklist_Item__c(
                            Id = item.itemId,
                            Item_Status__c = STATUS_NOT_APPLICABLE,
                            Review_Source__c = 'Agentforce Verify',
                            Reviewed_At__c = Datetime.now(),
                            Reviewed_By__c = 'Agentforce'
                        ));
                        processedIds.add(item.itemId);
                        response.itemsNotApplicable.add(item.title);
                    }
                }
            }
            
            // Mark remaining items as missed (if markMissed is true)
            if (markMissed == null || markMissed == true) {
                for (Map<String, Object> pendingItem : pendingItems) {
                    String itemTitle = (String) pendingItem.get('title');
                    Id itemId = itemTitleToId.get(itemTitle);
                    Boolean isConditional = (Boolean) pendingItem.get('isConditional');
                    Integer level = (Integer) pendingItem.get('level');
                    Decimal seq = (Decimal) pendingItem.get('sequence');
                    
                    if (itemId != null && !processedIds.contains(itemId)) {
                        Boolean parentIsNA = false;
                        if (level == 2 && seq != null) {
                            Integer parentSeq = seq.intValue();
                            parentIsNA = naParentSequences.contains(parentSeq);
                        }
                        
                        if (parentIsNA) {
                            itemsToUpdate.add(new Voice_Checklist_Item__c(
                                Id = itemId,
                                Item_Status__c = STATUS_NOT_APPLICABLE,
                                Review_Source__c = 'Agentforce Verify',
                                Reviewed_At__c = Datetime.now(),
                                Reviewed_By__c = 'Agentforce'
                            ));
                            processedIds.add(itemId);
                            response.itemsNotApplicable.add(itemTitle);
                        } else if (!isConditional || !notApplicableItems.contains(itemTitle)) {
                            itemsToUpdate.add(new Voice_Checklist_Item__c(
                                Id = itemId,
                                Item_Status__c = STATUS_MISSED,
                                Review_Source__c = 'Agentforce Verify',
                                Reviewed_At__c = Datetime.now(),
                                Reviewed_By__c = 'Agentforce'
                            ));
                            processedIds.add(itemId);
                            response.itemsMissed.add(itemTitle);
                        }
                    }
                }
            }
            
            // Handle manual items
            if (markMissed == null || markMissed == true) {
                for (Map<String, Object> manualItem : manualItems) {
                    String itemTitle = (String) manualItem.get('title');
                    Id itemId = itemTitleToId.get(itemTitle);
                    
                    if (itemId != null && !processedIds.contains(itemId) && notDiscussedItems.contains(itemTitle)) {
                        itemsToUpdate.add(new Voice_Checklist_Item__c(
                            Id = itemId,
                            Item_Status__c = STATUS_PENDING,
                            Review_Source__c = 'Needs Review',
                            Reviewed_At__c = Datetime.now(),
                            Reviewed_By__c = 'Agentforce'
                        ));
                        response.itemsNeedingReview.add(itemTitle);
                    }
                }
            }
            
            if (!itemsToUpdate.isEmpty()) {
                update itemsToUpdate;
            }
            
            response.isSuccess = true;
            response.updatedChecklist = getChecklistForParentRecord(parentRecordId);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'VoiceChecklistController.verifyChecklist: ' + e.getMessage() + '\n' + e.getStackTraceString());
            response.error = 'Verification error: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * @description Get transcript from a Flow
     */
    private static String getTranscriptFromFlow(Id recordId, String flowName) {
        try {
            String objectType = recordId.getSobjectType().getDescribe().getName();
            String inputVariableName = objectType == 'VoiceCall' ? 'voiceCallId' : 'messagingSessionId';
            
            Map<String, Object> flowInputs = new Map<String, Object>{
                inputVariableName => recordId
            };
            
            Flow.Interview flowInterview = Flow.Interview.createInterview(flowName, flowInputs);
            flowInterview.start();
            
            return (String) flowInterview.getVariableValue('transcriptText');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'VoiceChecklistController.getTranscriptFromFlow: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Build the verification prompt
     */
    private static String buildVerificationPrompt(String fullTranscript, List<Map<String, Object>> pendingItems, List<Map<String, Object>> manualItems) {
        String prompt = 'You are reviewing a customer service conversation to verify which checklist items were addressed.\n\n';
        prompt += 'IMPORTANT: Be INCLUSIVE in your evaluation. If the agent addressed the INTENT of a checklist item, mark it as discussed even if they didn\'t use the exact wording.\n\n';
        prompt += 'FULL TRANSCRIPT:\n' + fullTranscript + '\n\n';
        
        if (!pendingItems.isEmpty()) {
            prompt += 'CHECKLIST ITEMS TO VERIFY:\n';
            for (Map<String, Object> item : pendingItems) {
                prompt += '- ' + item.get('title') + ': ' + item.get('description');
                
                String hints = (String) item.get('hints');
                if (String.isNotBlank(hints)) {
                    prompt += ' [HINTS: ' + hints + ']';
                }
                
                Boolean isConditional = (Boolean) item.get('isConditional');
                String condition = (String) item.get('condition');
                if (isConditional == true) {
                    prompt += ' [CONDITIONAL';
                    if (String.isNotBlank(condition)) {
                        prompt += ': ' + condition;
                    }
                    prompt += ']';
                }
                prompt += '\n';
            }
            prompt += '\n';
        }
        
        if (!manualItems.isEmpty()) {
            prompt += 'MANUALLY CHECKED ITEMS TO CONFIRM:\n';
            for (Map<String, Object> item : manualItems) {
                prompt += '- ' + item.get('title') + ': ' + item.get('description');
                String hints = (String) item.get('hints');
                if (String.isNotBlank(hints)) {
                    prompt += ' [HINTS: ' + hints + ']';
                }
                prompt += '\n';
            }
            prompt += '\n';
        }
        
        prompt += 'EVALUATION GUIDELINES:\n';
        prompt += '1. BE INCLUSIVE: If the agent addressed the topic in ANY reasonable way, mark it as discussed.\n';
        prompt += '2. Focus on MEANING and INTENT, not exact word matches.\n';
        prompt += '3. Use the HINTS provided with each item to recognize equivalent phrases or actions.\n';
        prompt += '4. CRITICAL - N/A Rules:\n';
        prompt += '   - ONLY items marked [CONDITIONAL: condition] can be in notApplicableItems\n';
        prompt += '   - For CONDITIONAL items: FIRST determine if the condition was actually met\n';
        prompt += '     * If condition was NOT met → put in notApplicableItems\n';
        prompt += '     * If condition WAS met AND item was addressed → put in discussedItems\n';
        prompt += '     * If condition WAS met but item was NOT addressed → put in notDiscussedItems\n';
        prompt += '   - For NON-CONDITIONAL items (no [CONDITIONAL] tag):\n';
        prompt += '     * If addressed → put in discussedItems\n';
        prompt += '     * If NOT addressed → put in notDiscussedItems\n';
        prompt += '     * NEVER put non-conditional items in notApplicableItems - they are always required\n\n';
        prompt += 'Return ONLY a JSON object. Use ONLY the item name (text BEFORE the colon), not the description:\n';
        prompt += '{\n';
        prompt += '  "discussedItems": ["HIPAA Verification", "Walk Through EOB"],\n';
        prompt += '  "notDiscussedItems": ["Identify Specific Claim"],\n';
        prompt += '  "notApplicableItems": ["If Denied: Explain Reason"]\n';
        prompt += '}\n';
        prompt += '\nREMEMBER: Only conditional items where the condition was NOT met belong in notApplicableItems. Non-conditional items that are not discussed must go in notDiscussedItems, never in notApplicableItems.\n';
        
        return prompt;
    }
    
    /**
     * @description Parse verification response
     */
    private static Map<String, Object> parseVerificationResponse(String aiResponse) {
        Map<String, Object> result = new Map<String, Object>{
            'discussed' => new List<String>(),
            'notDiscussed' => new List<String>(),
            'notApplicable' => new List<String>()
        };
        
        try {
            Integer startIdx = aiResponse.indexOf('{');
            Integer endIdx = aiResponse.lastIndexOf('}');
            
            if (startIdx >= 0 && endIdx > startIdx) {
                String jsonStr = aiResponse.substring(startIdx, endIdx + 1);
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
                
                if (parsed.containsKey('discussedItems')) {
                    List<Object> items = (List<Object>) parsed.get('discussedItems');
                    List<String> discussed = new List<String>();
                    for (Object item : items) {
                        discussed.add(String.valueOf(item));
                    }
                    result.put('discussed', discussed);
                }
                
                if (parsed.containsKey('notDiscussedItems')) {
                    List<Object> items = (List<Object>) parsed.get('notDiscussedItems');
                    List<String> notDiscussed = new List<String>();
                    for (Object item : items) {
                        notDiscussed.add(String.valueOf(item));
                    }
                    result.put('notDiscussed', notDiscussed);
                }
                
                if (parsed.containsKey('notApplicableItems')) {
                    List<Object> items = (List<Object>) parsed.get('notApplicableItems');
                    List<String> notApplicable = new List<String>();
                    for (Object item : items) {
                        notApplicable.add(String.valueOf(item));
                    }
                    result.put('notApplicable', notApplicable);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'VoiceChecklistController.parseVerificationResponse: ' + e.getMessage());
        }
        
        return result;
    }
}