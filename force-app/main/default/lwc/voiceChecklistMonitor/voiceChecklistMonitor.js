import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';

// Conversation Toolkit for messaging
import { getConversationLog, setAgentInput, sendTextMessage } from 'lightning/conversationToolkitApi';

// Apex methods
import getActiveTemplates from '@salesforce/apex/VoiceChecklistController.getActiveTemplates';
import selectTemplateForSession from '@salesforce/apex/VoiceChecklistController.selectTemplateForSession';
import getChecklistForParentRecord from '@salesforce/apex/VoiceChecklistController.getChecklistForParentRecord';
import updateItemStatus from '@salesforce/apex/VoiceChecklistController.updateItemStatus';
import evaluateTranscript from '@salesforce/apex/VoiceChecklistController.evaluateTranscript';
import verifyChecklist from '@salesforce/apex/VoiceChecklistController.verifyChecklist';

// Listening states
const STATE_NOT_STARTED = 'not_started';
const STATE_LISTENING = 'listening';
const STATE_PAUSED = 'paused';
const STATE_DONE = 'done';

// Review status values
const STATUS_PENDING = 'Pending';
const STATUS_COMPLETED_AI = 'Completed (AI)';
const STATUS_COMPLETED_MANUAL = 'Completed (Manual)';
const STATUS_NOT_APPLICABLE = 'Not Applicable';
const STATUS_MISSED = 'Missed';

// Default word threshold for batching
const DEFAULT_BATCH_THRESHOLD = 50;

// MessagingSession status field
const MESSAGING_STATUS_FIELD = 'MessagingSession.Status';

export default class VoiceChecklistMonitor extends LightningElement {
    @api recordId; // Voice Call or Messaging Session record ID
    
    // Shared properties
    @api cardTitle = 'Checklist';
    @api componentHeight = 400;
    @api darkMode = false;
    @api instructionFontSize = 'medium';
    @api batchWordThreshold = DEFAULT_BATCH_THRESHOLD;
    @api trackCustomerSpeech = false;
    @api evaluatorFlowBaseName = 'Voice_Checklist_Evaluator';
    
    // Boolean properties that default to true (use backing field pattern)
    _showChecklistTitle;
    _allowPause;
    _requireStartButton;
    
    @api
    get showChecklistTitle() {
        return this._showChecklistTitle !== false;
    }
    set showChecklistTitle(value) {
        this._showChecklistTitle = value;
    }
    
    @api
    get allowPause() {
        return this._allowPause !== false;
    }
    set allowPause(value) {
        this._allowPause = value;
    }
    
    @api
    get requireStartButton() {
        return this._requireStartButton !== false;
    }
    set requireStartButton(value) {
        this._requireStartButton = value;
    }
    
    // Voice-only properties
    @api transcriptFlowName = 'Get_Voice_Call_Transcript';
    
    // Messaging-only properties
    @api messagingPollInterval; // No default - empty/undefined means manual mode
    @api messagingTranscriptFlowName = 'Get_Messaging_Session_Transcript';

    @track checklistData = null;
    @track templates = [];
    @track selectedTemplateId = null;
    @track isLoading = true;
    @track isSelectingTemplate = false;
    @track listeningState = STATE_NOT_STARTED;
    @track isVerifying = false;
    @track collapsedItems = new Set();

    // Session type detection
    _isVoiceCall = false;
    _isMessagingSession = false;
    
    // Shared transcript state
    _transcriptBuffer = '';
    _wordCount = 0;
    _isProcessingTranscript = false;
    
    // Voice-specific state
    _voiceToolkitSubscribed = false;
    _callEndedProcessed = false;
    
    // Messaging-specific state
    _pollingInterval = null;
    _lastProcessedMessages = [];
    _pollingErrorCount = 0;
    _sessionEndedProcessed = false;

    // ===== Lifecycle =====

    connectedCallback() {
        console.log('Checklist Monitor: Connected', this.recordId);
        this.detectSessionType();
        this.loadChecklist();
    }

    renderedCallback() {
        if (this._isVoiceCall && !this._voiceToolkitSubscribed) {
            const voiceToolkit = this.template.querySelector('lightning-service-cloud-voice-toolkit-api');
            if (voiceToolkit) {
                console.log('Checklist Monitor: Voice toolkit found');
            }
        }
    }

    disconnectedCallback() {
        this.stopMessagingMonitoring();
    }

    // ===== Session Type Detection =====

    detectSessionType() {
        if (!this.recordId) return;
        
        const prefix = this.recordId.substring(0, 3);
        
        if (prefix === '0LQ') {
            this._isVoiceCall = true;
            this._isMessagingSession = false;
            console.log('Checklist Monitor: Detected VoiceCall');
        } else if (prefix === '0Mw') {
            this._isMessagingSession = true;
            this._isVoiceCall = false;
            console.log('Checklist Monitor: Detected MessagingSession');
        } else {
            console.warn('Checklist Monitor: Unknown record type, prefix:', prefix);
        }
    }

    // ===== Wire Methods =====

    @wire(getActiveTemplates)
    wiredTemplates({ error, data }) {
        if (data) {
            this.templates = data;
            console.log('Checklist Monitor: Templates loaded', data.length);
        } else if (error) {
            console.error('Checklist Monitor: Error loading templates', error);
        }
    }

    // Wire for MessagingSession status changes
    @wire(getRecord, { recordId: '$recordId', fields: [MESSAGING_STATUS_FIELD] })
    wiredMessagingSession({ data, error }) {
        if (data && this._isMessagingSession) {
            const status = data.fields?.Status?.value;
            if (status === 'Ended' && !this._sessionEndedProcessed) {
                this.handleSessionEnded();
            }
        }
    }

    // ===== Checklist Loading =====

    async loadChecklist() {
        this.isLoading = true;
        try {
            const result = await getChecklistForParentRecord({ parentRecordId: this.recordId });
            this.checklistData = result;
            console.log('Checklist Monitor: Checklist loaded', result);
        } catch (error) {
            console.error('Checklist Monitor: Error loading checklist', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ===== Getters =====

    get hasChecklist() {
        return this.checklistData && this.checklistData.checklist;
    }

    get showTemplatePicker() {
        return !this.isLoading && !this.hasChecklist;
    }

    get showChecklist() {
        return !this.isLoading && this.hasChecklist;
    }

    get hasTemplates() {
        return this.templates && this.templates.length > 0;
    }

    get templateOptions() {
        return this.templates.map(t => {
            let label = t.name;
            if (t.version) {
                label += ' v' + t.version;
            }
            label += ' (' + t.itemCount + ' items)';
            return {
                label: label,
                value: t.templateId
            };
        });
    }

    get selectedTemplateDescription() {
        if (!this.selectedTemplateId) return '';
        const template = this.templates.find(t => t.templateId === this.selectedTemplateId);
        return template ? template.description : '';
    }

    get effectiveTitle() {
        const useChecklistTitle = this.showChecklistTitle !== false;
        if (useChecklistTitle && this.checklistData?.checklist?.templateName) {
            return this.checklistData.checklist.templateName;
        }
        return this.cardTitle || 'Checklist';
    }

    get containerStyle() {
        const height = this.componentHeight || 400;
        return `height: ${height}px; overflow-y: auto;`;
    }

    get cardClass() {
        return this.darkMode ? 'dark-mode' : '';
    }

    get cardIcon() {
        if (this._isVoiceCall) return 'standard:voice_call';
        if (this._isMessagingSession) return 'standard:live_chat';
        return 'standard:task';
    }

    get instructionFontStyle() {
        const sizeMap = {
            'small': '12px',
            'medium': '14px',
            'large': '16px'
        };
        const fontSize = sizeMap[this.instructionFontSize] || '14px';
        return `font-size: ${fontSize};`;
    }

    get showPauseButton() {
        return this.allowPause !== false;
    }

    // ===== Voice Toolkit Conditional Rendering =====

    get showVoiceToolkit() {
        return this._isVoiceCall;
    }

    // ===== Manual Mode Detection =====

    get isManualVerificationMode() {
        if (!this._isMessagingSession) return false;
        
        // Manual mode if: 0, '0', empty string, null, or undefined
        const pollInterval = this.messagingPollInterval;
        return pollInterval === 0 || 
               pollInterval === '0' || 
               pollInterval === '' || 
               pollInterval == null || 
               pollInterval === undefined;
    }

    get showManualModeInfoBanner() {
        return this.isManualVerificationMode && 
               this.listeningState === STATE_LISTENING;
    }

    get showTopVerifyButton() {
        return this.isManualVerificationMode && 
               this.listeningState === STATE_LISTENING &&
               !this.isVerifying;
    }

    get manualModeBannerMessage() {
        return 'Auto-checking is disabled. Click "Verify Now" to evaluate your conversation against the checklist.';
    }

    get topVerifyButtonLabel() {
        return 'Verify Now';
    }

    // ===== Progress Display =====

    get showProgressIndicator() {
        if (this.listeningState !== STATE_LISTENING) return false;
        if (this._isProcessingTranscript) return true;
        if (this.isManualVerificationMode) return false;
        return true;
    }

    get progressDisplay() {
        if (this._isProcessingTranscript) {
            return 'Checking...';
        }
        const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
        return `${this._wordCount}/${threshold}`;
    }

    get progressBadgeClass() {
        if (this._isProcessingTranscript) {
            return 'progress-badge progress-badge-checking';
        }
        return 'progress-badge';
    }

    // ===== Status Badge =====

    get statusBadgeLabel() {
        if (this.listeningState === STATE_NOT_STARTED) return 'NOT STARTED';
        if (this.listeningState === STATE_PAUSED) return 'PAUSED';
        if (this.listeningState === STATE_DONE) {
            return this._isVoiceCall ? 'CALL ENDED' : 'SESSION ENDED';
        }
        if (this.listeningState === STATE_LISTENING) {
            if (this.isManualVerificationMode) return 'MANUAL MODE';
            return this._isVoiceCall ? 'LISTENING' : 'MONITORING';
        }
        return '';
    }

    get statusBadgeClass() {
        switch (this.listeningState) {
            case STATE_NOT_STARTED: return 'slds-badge';
            case STATE_LISTENING: return 'slds-badge slds-theme_success';
            case STATE_PAUSED: return 'slds-badge slds-theme_warning';
            case STATE_DONE: return 'slds-badge slds-theme_inverse';
            default: return 'slds-badge';
        }
    }

    // ===== Checklist Items =====

    get checklistItems() {
        const items = this.checklistData?.items || [];
        return items.map(item => {
            const isCompleted = item.itemStatus === STATUS_COMPLETED_AI || 
                               item.itemStatus === STATUS_COMPLETED_MANUAL;
            const isNotApplicable = item.itemStatus === STATUS_NOT_APPLICABLE;
            const isMissed = item.itemStatus === STATUS_MISSED;
            const isPending = !item.itemStatus || item.itemStatus === STATUS_PENDING;
            
            let itemClass = 'checklist-item';
            if (item.isChild) itemClass += ' child-item';
            if (item.isConditional) itemClass += ' conditional-item';
            if (isCompleted) itemClass += ' completed';
            else if (isNotApplicable) itemClass += ' not-applicable';
            else if (isMissed) itemClass += ' missed';

            let iconName = 'utility:circle';
            let iconVariant = '';
            let iconClass = 'item-icon icon-pending';
            
            if (isCompleted) {
                iconName = 'utility:success';
                iconVariant = 'success';
                iconClass = 'item-icon';
            } else if (isNotApplicable) {
                iconName = 'utility:dash';
                iconClass = 'item-icon icon-na';
            } else if (isMissed) {
                iconName = 'utility:warning';
                iconVariant = 'error';
                iconClass = 'item-icon';
            } else if (item.isConditional && isPending) {
                iconName = 'utility:routing_offline';
                iconClass = 'item-icon icon-conditional';
            }

            const sequenceDisplay = item.checklistLevel === 2 ? '' : Math.floor(item.itemSequence) + '.';
            
            let titleClass = 'item-title';
            if (isCompleted) titleClass += ' completed';
            else if (isNotApplicable) titleClass += ' not-applicable';
            else if (isMissed) titleClass += ' missed';
            
            let badgeLabel = '';
            let badgeClass = 'slds-hide';
            const hasInstructions = item.userInstructions && item.userInstructions.trim() !== '';

            if (item.reviewSource) {
                switch (item.reviewSource) {
                    case 'Agentforce Auto':
                        badgeLabel = 'AUTO';
                        badgeClass = 'slds-badge badge-auto';
                        break;
                    case 'Agentforce Verify':
                        badgeLabel = 'VERIFIED';
                        badgeClass = 'slds-badge badge-auto';
                        break;
                    case 'Manual Override':
                        badgeLabel = 'MANUAL';
                        badgeClass = 'slds-badge badge-manual';
                        break;
                    case 'Needs Review':
                        badgeLabel = 'NEEDS REVIEW';
                        badgeClass = 'slds-badge badge-needs-review';
                        break;
                    case 'Incomplete':
                        badgeLabel = 'INCOMPLETE';
                        badgeClass = 'slds-badge badge-incomplete';
                        break;
                    default:
                        badgeClass = 'slds-badge';
                }
            }
            
            if (isNotApplicable) {
                badgeLabel = 'N/A';
                badgeClass = 'slds-badge badge-na';
            } else if (isMissed) {
                badgeLabel = 'MISSED';
                badgeClass = 'slds-badge badge-missed';
            }

            let conditionalLabel = '';
            if (item.isConditional && item.conditionDescription) {
                conditionalLabel = item.conditionDescription;
            } else if (item.isConditional) {
                conditionalLabel = 'Conditional';
            }

            const isExpanded = hasInstructions && !this.collapsedItems.has(item.itemId);
            const expandIconName = isExpanded ? 'utility:chevrondown' : 'utility:chevronright';

            // Quick Insert/Send buttons - only show for Messaging Sessions
            const showQuickInsert = this._isMessagingSession && item.enableQuickInsert;
            const showQuickSend = this._isMessagingSession && item.enableQuickSend;
            const quickInsertText = item.quickInsertText || item.userInstructions || '';

            return {
                ...item,
                isCompleted,
                isNotApplicable,
                isMissed,
                isPending,
                computedClass: itemClass,
                computedIconName: iconName,
                computedIconVariant: iconVariant,
                computedIconClass: iconClass,
                computedSequence: sequenceDisplay,
                computedTitleClass: titleClass,
                computedBadgeLabel: badgeLabel,
                computedBadgeClass: badgeClass,
                hasBadge: badgeLabel !== '',
                hasInstructions,
                isExpanded,
                expandIconName,
                conditionalLabel,
                showConditionalIndicator: item.isConditional && isPending,
                showQuickInsert,
                showQuickSend,
                quickInsertText,
                hasQuickActions: showQuickInsert || showQuickSend
            };
        });
    }

    get hasPendingItems() {
        return this.checklistItems.some(item => item.isPending);
    }

    get completionStats() {
        if (!this.checklistData?.items) return { completed: 0, total: 0, notApplicable: 0, missed: 0 };
        
        const items = this.checklistData.items;
        const completed = items.filter(i => 
            i.itemStatus === STATUS_COMPLETED_AI || 
            i.itemStatus === STATUS_COMPLETED_MANUAL
        ).length;
        const notApplicable = items.filter(i => i.itemStatus === STATUS_NOT_APPLICABLE).length;
        const missed = items.filter(i => i.itemStatus === STATUS_MISSED).length;
        const total = items.length;
        
        return { completed, total, notApplicable, missed };
    }

    get completionText() {
        const stats = this.completionStats;
        let text = `${stats.completed} completed`;
        if (stats.missed > 0) {
            text += ` · ${stats.missed} missed`;
        }
        return text;
    }

    get completionSecondaryText() {
        const stats = this.completionStats;
        let parts = [];
        if (stats.notApplicable > 0) {
            parts.push(`${stats.notApplicable} N/A`);
        }
        parts.push(`${stats.total} total items`);
        return parts.join(' · ');
    }

    get completionPercentage() {
        const stats = this.completionStats;
        const applicableItems = stats.total - stats.notApplicable;
        if (applicableItems === 0) return 100;
        return Math.round((stats.completed / applicableItems) * 100);
    }

    get progressBarStyle() {
        return `width: ${this.completionPercentage}%`;
    }

    get progressBarClass() {
        const stats = this.completionStats;
        if (stats.missed > 0) {
            return 'progress-bar progress-warning';
        }
        return 'progress-bar';
    }

    get effectiveEvaluatorFlowBaseName() {
        return this.evaluatorFlowBaseName || 'Voice_Checklist_Evaluator';
    }

    get effectiveTranscriptFlowName() {
        if (this._isVoiceCall) {
            return this.transcriptFlowName || 'Get_Voice_Call_Transcript';
        }
        return this.messagingTranscriptFlowName || 'Get_Messaging_Session_Transcript';
    }

    // ===== Button States =====

    get pauseButtonLabel() {
        if (this.isVerifying && this.listeningState === STATE_NOT_STARTED) {
            return 'Starting...';
        }
        switch (this.listeningState) {
            case STATE_NOT_STARTED: return 'Start';
            case STATE_LISTENING: return 'Pause';
            case STATE_PAUSED: return 'Resume';
            case STATE_DONE: return 'Done';
            default: return 'Start';
        }
    }

    get pauseButtonDisabled() {
        return this.listeningState === STATE_DONE || this.isVerifying;
    }

    get pauseButtonVariant() {
        switch (this.listeningState) {
            case STATE_NOT_STARTED: return 'brand';
            case STATE_LISTENING: return 'neutral';
            case STATE_PAUSED: return 'brand';
            case STATE_DONE: return 'neutral';
            default: return 'neutral';
        }
    }

    get pauseButtonIconName() {
        switch (this.listeningState) {
            case STATE_NOT_STARTED: return 'utility:play';
            case STATE_LISTENING: return 'utility:pause';
            case STATE_PAUSED: return 'utility:play';
            case STATE_DONE: return 'utility:check';
            default: return 'utility:play';
        }
    }

    get verifyButtonDisabled() {
        return this.isVerifying || this.listeningState === STATE_DONE;
    }

    get verifyButtonVariant() {
        if (this.isManualVerificationMode && this.hasPendingItems) {
            return 'brand';
        }
        return 'neutral';
    }

    // ===== Template Picker Methods =====

    handleTemplateSelect(event) {
        this.selectedTemplateId = event.target.value;
    }

    async handleApplyTemplate() {
        if (!this.selectedTemplateId) {
            this.showToast('Error', 'Please select a template', 'error');
            return;
        }

        this.isSelectingTemplate = true;

        try {
            await selectTemplateForSession({ 
                sessionId: this.recordId, 
                templateId: this.selectedTemplateId 
            });

            this.showToast('Success', 'Template applied. Checklist will be created.', 'success');
            
            setTimeout(async () => {
                await this.loadChecklist();
                
                if (this.requireStartButton === false && this.hasChecklist) {
                    console.log('Checklist Monitor: Auto-starting monitoring');
                    this.verifyAndStartListening();
                }
            }, 2000);

        } catch (error) {
            console.error('Checklist Monitor: Error applying template', error);
            this.showToast('Error', 'Failed to apply template: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isSelectingTemplate = false;
        }
    }

    // ===== Checklist Item Methods =====

    handleExpandToggle(event) {
        event.stopPropagation();
        const itemId = event.currentTarget.dataset.itemId;
        
        if (this.collapsedItems.has(itemId)) {
            this.collapsedItems.delete(itemId);
        } else {
            this.collapsedItems.add(itemId);
        }
        this.collapsedItems = new Set(this.collapsedItems);
    }

    async handleItemClick(event) {
        const itemId = event.currentTarget.dataset.itemId;
        const item = this.checklistItems.find(i => i.itemId === itemId);
        
        if (!item) return;

        if (item.itemStatus === STATUS_COMPLETED_AI || 
            item.reviewSource === 'Agentforce Auto' || 
            item.reviewSource === 'Agentforce Verify') {
            this.showToast('Info', 'AI-verified items cannot be unchecked', 'info');
            return;
        }
        
        if (item.isNotApplicable) {
            this.showToast('Info', 'N/A items cannot be changed', 'info');
            return;
        }

        let newStatus;
        if (item.isMissed) {
            newStatus = STATUS_COMPLETED_MANUAL;
        } else {
            newStatus = item.isCompleted ? STATUS_PENDING : STATUS_COMPLETED_MANUAL;
        }

        try {
            const result = await updateItemStatus({ 
                itemId: itemId, 
                newStatus: newStatus 
            });
            this.checklistData = result;
            
            if (item.isMissed) {
                this.showToast('Success', 'Item marked as completed', 'success');
            }
        } catch (error) {
            console.error('Checklist Monitor: Error updating item', error);
            this.showToast('Error', 'Failed to update item: ' + this.reduceErrors(error), 'error');
        }
    }

    handleRefresh() {
        this.loadChecklist();
    }

    // ===== Listening Control Methods =====

    async handlePauseToggle() {
        switch (this.listeningState) {
            case STATE_NOT_STARTED:
                await this.verifyAndStartListening();
                break;
            case STATE_LISTENING:
                this.listeningState = STATE_PAUSED;
                if (this._isMessagingSession) {
                    this.stopMessagingMonitoring();
                }
                break;
            case STATE_PAUSED:
                this.listeningState = STATE_LISTENING;
                if (this._isMessagingSession && !this.isManualVerificationMode) {
                    this.startMessagingMonitoring();
                }
                break;
            case STATE_DONE:
                break;
        }
    }

    async verifyAndStartListening() {
        this.isVerifying = true;

        try {
            const result = await verifyChecklist({
                parentRecordId: this.recordId,
                transcriptFlowName: this.effectiveTranscriptFlowName,
                evaluatorFlowName: this.effectiveEvaluatorFlowBaseName + '_Flow',
                markMissed: false
            });

            console.log('Checklist Monitor: Initial verify result:', JSON.stringify(result));

            if (result.isSuccess) {
                if (result.updatedChecklist) {
                    this.checklistData = result.updatedChecklist;
                }

                let toastMessage = 'Verified: ' + (result.itemsVerified?.length || 0) + ' item(s) found - Now monitoring';
                this.showToast('Started', toastMessage, 'success');
            } else {
                this.showToast('Started', 'Could not verify transcript, but now monitoring', 'warning');
            }

            this.listeningState = STATE_LISTENING;

            // Start messaging polling if applicable
            if (this._isMessagingSession && !this.isManualVerificationMode) {
                this.startMessagingMonitoring();
            }

        } catch (error) {
            console.error('Checklist Monitor: Error during verification:', error);
            this.showToast('Started', 'Verification error, but now monitoring', 'warning');
            this.listeningState = STATE_LISTENING;
            
            if (this._isMessagingSession && !this.isManualVerificationMode) {
                this.startMessagingMonitoring();
            }
        } finally {
            this.isVerifying = false;
        }
    }

    // ===== Messaging Polling Methods =====

    startMessagingMonitoring() {
        // Don't start if already polling or in manual mode
        if (this._pollingInterval || this.isManualVerificationMode) return;
        
        // Get interval value - should have a valid value if not in manual mode
        // Default to 5000 for backward compatibility if somehow invalid
        const pollInterval = this.messagingPollInterval;
        const interval = Number(pollInterval) || 5000;
        
        this._pollingInterval = setInterval(() => {
            if (this.listeningState === STATE_LISTENING) {
                this.fetchAndProcessMessages();
            }
        }, interval);
        
        // Initial fetch
        this.fetchAndProcessMessages();
        console.log('Checklist Monitor: Started messaging polling at', interval, 'ms');
    }

    stopMessagingMonitoring() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
            console.log('Checklist Monitor: Stopped messaging polling');
        }
    }

    async fetchAndProcessMessages() {
        try {
            console.log('Checklist Monitor: Calling getConversationLog with recordId:', this.recordId);
            const response = await getConversationLog(this.recordId);
            console.log('Checklist Monitor: Raw response:', response);
            
            // getConversationLog returns {messages: [...]} not an array directly
            const messages = response?.messages || [];
            console.log('Checklist Monitor: Messages array length:', messages.length);
            
            const newMessages = this.getNewMessages(messages);
            console.log('Checklist Monitor: New messages to process:', newMessages.length);
            
            if (newMessages.length === 0) return;
            
            // Reset error count on success
            this._pollingErrorCount = 0;
            
            // Process each new message
            for (const msg of newMessages) {
                if (!this.shouldIncludeMessage(msg)) continue;
                
                // API returns 'content' not 'messageText'
                const text = msg.content || msg.messageText || '';
                const wordCount = this.countWords(text);
                
                this._transcriptBuffer += (this._transcriptBuffer ? '\n' : '') + text;
                this._wordCount += wordCount;
            }
            
            // Update tracking
            this._lastProcessedMessages = [...this._lastProcessedMessages, ...newMessages];
            
            // Check threshold
            const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
            if (this._wordCount >= threshold) {
                console.log('Checklist Monitor: Threshold reached, processing batch');
                await this.processTranscriptBatch(false);
            }
        } catch (error) {
            this._pollingErrorCount++;
            console.error('Checklist Monitor: Polling error', error);
            
            if (this._pollingErrorCount >= 3) {
                this.stopMessagingMonitoring();
                this.showToast('Auto-Check Paused', 
                    'Unable to retrieve messages. Please use the Verify button.', 
                    'warning');
            }
        }
    }

    getNewMessages(allMessages) {
        if (!allMessages || !Array.isArray(allMessages)) return [];
        // Use timestamp as unique identifier since messages don't have id
        const processedTimestamps = new Set(this._lastProcessedMessages.map(m => m.timestamp));
        return allMessages.filter(m => !processedTimestamps.has(m.timestamp));
    }

    shouldIncludeMessage(msg) {
        // API returns 'type' not 'actorType', values are 'Agent', 'EndUser', 'System'
        const actorType = msg.type || msg.actorType || msg.ActorType || '';
        const actorLower = actorType.toLowerCase();
        const isAgent = actorLower === 'agent';
        const isCustomer = actorLower === 'enduser' || actorLower === 'customer';
        
        return isAgent || (this.trackCustomerSpeech && isCustomer);
    }

    // ===== Voice Event Handlers =====

    handleVoiceConversationEvent(event) {
        console.log('Checklist Monitor: Voice event received', event?.type);
        
        if (!event || !event.type || !event.detail) {
            console.log('Checklist Monitor: Event missing type or detail, ignoring');
            return;
        }
        
        const eventType = event.type.replace(/^on/, '');
        
        if (eventType === 'transcript' && this.listeningState !== STATE_LISTENING) {
            console.log('Checklist Monitor: Not listening, ignoring transcript');
            return;
        }

        const detail = event.detail;
        this._voiceToolkitSubscribed = true;
        
        console.log('Checklist Monitor: Processing event type:', eventType);

        try {
            if (eventType === 'transcript') {
                this.handleTranscript(detail);
            } else if (eventType === 'callstarted') {
                this.handleCallStarted(detail);
            } else if (eventType === 'callended') {
                this.handleCallEnded(detail);
            }
        } catch (err) {
            console.error('Checklist Monitor: Error handling voice event:', err);
        }
    }

    handleTranscript(detail) {
        const actorType = detail.actorType || detail.ActorType || 
                         (detail.sender ? (detail.sender.actorType || detail.sender.role) : null);
        const rawText = detail.content ? detail.content.text : (detail.message || detail.Message);

        console.log('Checklist Monitor: Transcript received - ActorType:', actorType, 'Text:', rawText?.substring(0, 50));

        const actorLower = actorType ? actorType.toLowerCase() : '';
        const isAgent = actorLower === 'agent';
        const isCustomer = actorLower === 'enduser' || actorLower === 'customer';
        
        if (!actorType || !rawText || !rawText.trim()) {
            console.log('Checklist Monitor: Skipping - missing actorType or text');
            return;
        }
        
        if (!isAgent && !(this.trackCustomerSpeech && isCustomer)) {
            console.log('Checklist Monitor: Skipping - ActorType:', actorType);
            return;
        }

        const decodedText = this.decodeHtmlEntities(rawText.trim());
        const wordCount = this.countWords(decodedText);

        this._transcriptBuffer += (this._transcriptBuffer ? ' ' : '') + decodedText;
        this._wordCount += wordCount;

        console.log('Checklist Monitor: Buffer word count:', this._wordCount, '/', this.batchWordThreshold);

        const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
        if (this._wordCount >= threshold) {
            console.log('Checklist Monitor: Threshold reached, processing batch');
            this.processTranscriptBatch(false);
        }
    }

    handleCallStarted(detail) {
        const eventVoiceCallId = detail?.voiceCallId || detail?.recordId;
        if (eventVoiceCallId && eventVoiceCallId !== this.recordId) {
            console.log('Checklist Monitor: Ignoring callstarted for different voice call:', eventVoiceCallId);
            return;
        }
        
        this._transcriptBuffer = '';
        this._wordCount = 0;
        this._callEndedProcessed = false;
        this.loadChecklist();
    }

    async handleCallEnded(detail) {
        const eventVoiceCallId = detail?.voiceCallId || detail?.recordId;
        if (eventVoiceCallId && eventVoiceCallId !== this.recordId) {
            console.log('Checklist Monitor: Ignoring callended for different voice call:', eventVoiceCallId);
            return;
        }
        
        if (this._callEndedProcessed) {
            console.log('Checklist Monitor: Call ended already processed, skipping');
            return;
        }
        this._callEndedProcessed = true;
        
        await this.runFinalVerification('Call');
    }

    async handleSessionEnded() {
        if (this._sessionEndedProcessed) return;
        this._sessionEndedProcessed = true;
        
        this.stopMessagingMonitoring();
        await this.runFinalVerification('Session');
    }

    async runFinalVerification(sessionType) {
        console.log('Checklist Monitor:', sessionType, 'ended, running final verification');
        
        this.listeningState = STATE_DONE;
        this.isVerifying = true;
        
        try {
            const result = await verifyChecklist({
                parentRecordId: this.recordId,
                transcriptFlowName: this.effectiveTranscriptFlowName,
                evaluatorFlowName: this.effectiveEvaluatorFlowBaseName + '_Flow',
                markMissed: true
            });
            
            console.log('Checklist Monitor: Final verification result:', JSON.stringify(result));
            
            if (result.isSuccess) {
                if (result.updatedChecklist) {
                    this.checklistData = result.updatedChecklist;
                }
                
                let toastMessage = sessionType + ' ended';
                const stats = this.completionStats;
                if (stats.completed > 0) {
                    toastMessage += ` - ${stats.completed} completed`;
                }
                if (stats.notApplicable > 0) {
                    toastMessage += `, ${stats.notApplicable} N/A`;
                }
                if (stats.missed > 0) {
                    toastMessage += `, ${stats.missed} missed`;
                }
                
                this.showToast(sessionType + ' Complete', toastMessage, stats.missed > 0 ? 'warning' : 'info');
            }
            
        } catch (err) {
            console.error('Checklist Monitor: Error during final verification:', err);
        } finally {
            this.isVerifying = false;
        }
    }

    handleVoiceToolkitError(event) {
        console.error('Checklist Monitor: Voice Toolkit error:', event.detail);
        this.showToast('Voice Connection Error', 
                       event.detail?.message || 'An error occurred with voice services.', 
                       'error');
    }

    // ===== Transcript Processing =====

    async processTranscriptBatch(forceFlush) {
        console.log('Checklist Monitor: processTranscriptBatch called, forceFlush:', forceFlush);
        
        if (this._isProcessingTranscript) {
            console.log('Checklist Monitor: Already processing, skipping');
            return;
        }

        const transcript = this._transcriptBuffer.trim();
        if (!transcript) {
            console.log('Checklist Monitor: No transcript to process');
            return;
        }

        this._isProcessingTranscript = true;
        this._transcriptBuffer = '';
        this._wordCount = 0;

        try {
            console.log('Checklist Monitor: Calling evaluateTranscript');
            const result = await evaluateTranscript({
                parentRecordId: this.recordId,
                transcript: transcript,
                evaluatorFlowName: this.effectiveEvaluatorFlowBaseName + '_Flow'
            });

            console.log('Checklist Monitor: Evaluate result:', JSON.stringify(result));

            if (result.isSuccess && result.updatedChecklist) {
                this.checklistData = result.updatedChecklist;
                
                if (result.itemsCompleted && result.itemsCompleted.length > 0) {
                    console.log('Checklist Monitor: Items completed:', result.itemsCompleted);
                }
            } else if (result.error) {
                console.error('Checklist Monitor: Evaluation error:', result.error);
            }
        } catch (error) {
            console.error('Checklist Monitor: Error in processTranscriptBatch:', error);
        } finally {
            this._isProcessingTranscript = false;
        }
    }

    // ===== Verify Button Handler =====

    async handleVerifyChecklist() {
        this.isVerifying = true;

        try {
            const result = await verifyChecklist({
                parentRecordId: this.recordId,
                transcriptFlowName: this.effectiveTranscriptFlowName,
                evaluatorFlowName: this.effectiveEvaluatorFlowBaseName + '_Flow',
                markMissed: true
            });

            console.log('Checklist Monitor: Verify result:', JSON.stringify(result));

            if (result.isSuccess) {
                if (result.updatedChecklist) {
                    this.checklistData = result.updatedChecklist;
                }

                let message = '';
                if (result.itemsVerified?.length > 0) {
                    message += result.itemsVerified.length + ' item(s) verified. ';
                }
                if (result.itemsNeedingReview?.length > 0) {
                    message += result.itemsNeedingReview.length + ' item(s) need review. ';
                }
                if (result.itemsNotApplicable?.length > 0) {
                    message += result.itemsNotApplicable.length + ' item(s) not applicable. ';
                }
                if (!message) {
                    message = 'Verification complete.';
                }

                this.showToast('Verification Complete', message.trim(), 'success');
            } else {
                this.showToast('Verification Failed', result.error || 'Unknown error', 'error');
            }

        } catch (error) {
            console.error('Checklist Monitor: Error verifying:', error);
            this.showToast('Error', 'Verification failed: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isVerifying = false;
        }
    }

    // ===== Quick Insert/Send Methods (Messaging Sessions) =====

    /**
     * Handles the Quick Insert button click - inserts text into agent's chat composer
     * for review/editing before sending
     */
    async handleQuickInsert(event) {
        event.stopPropagation(); // Prevent item click handler from firing
        
        const itemId = event.currentTarget.dataset.itemId;
        const item = this.checklistItems.find(i => i.itemId === itemId);
        
        if (!item || !item.quickInsertText) {
            this.showToast('No Text Available', 'This item has no text configured for quick insert.', 'warning');
            return;
        }

        try {
            // Strip HTML tags from the text for plain text insertion
            const plainText = this.stripHtml(item.quickInsertText);
            
            const result = await setAgentInput(this.recordId, { text: plainText });
            console.log('Checklist Monitor: Quick insert result:', result);
            
            this.showToast('Text Inserted', 'Text has been inserted into the chat composer. Review and send when ready.', 'success');
            
        } catch (error) {
            console.error('Checklist Monitor: Quick insert error:', error);
            this.showToast('Insert Failed', 'Could not insert text into chat: ' + this.reduceErrors(error), 'error');
        }
    }

    /**
     * Handles the Quick Send button click - immediately sends text to the customer
     */
    async handleQuickSend(event) {
        event.stopPropagation(); // Prevent item click handler from firing
        
        const itemId = event.currentTarget.dataset.itemId;
        const item = this.checklistItems.find(i => i.itemId === itemId);
        
        if (!item || !item.quickInsertText) {
            this.showToast('No Text Available', 'This item has no text configured for quick send.', 'warning');
            return;
        }

        try {
            // Strip HTML tags from the text for plain text sending
            const plainText = this.stripHtml(item.quickInsertText);
            
            const result = await sendTextMessage(this.recordId, { text: plainText });
            console.log('Checklist Monitor: Quick send result:', result);
            
            this.showToast('Message Sent', 'Message has been sent to the customer.', 'success');
            
        } catch (error) {
            console.error('Checklist Monitor: Quick send error:', error);
            this.showToast('Send Failed', 'Could not send message: ' + this.reduceErrors(error), 'error');
        }
    }

    /**
     * Strips HTML tags from text for plain text insertion/sending
     */
    stripHtml(html) {
        if (!html) return '';
        const temp = document.createElement('div');
        temp.innerHTML = html;
        return temp.textContent || temp.innerText || '';
    }

    // ===== Utility Methods =====

    decodeHtmlEntities(text) {
        const textarea = document.createElement('textarea');
        textarea.innerHTML = text;
        return textarea.value;
    }

    countWords(text) {
        if (!text) return 0;
        return text.split(/\s+/).filter(word => word.length > 0).length;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error.message) return error.message;
        if (error.body?.message) return error.body.message;
        return JSON.stringify(error);
    }
}