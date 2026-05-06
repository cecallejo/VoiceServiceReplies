import { LightningElement, wire, api, track } from 'lwc';
import {
    subscribe,
    unsubscribe,
    APPLICATION_SCOPE,
    MessageContext,
} from 'lightning/messageService';
import ConversationEndUserChannel from '@salesforce/messageChannel/lightning__conversationEndUserMessage';
import ConversationEndedChannel from '@salesforce/messageChannel/lightning__conversationEnded';
//import ConversationAgentSendChannel from '@salesforce/messageChannel/lightning__conversationAgentSend';
import { getRecord, updateRecord, getFieldValue } from 'lightning/uiRecordApi';
import CUSTOMER_SENTIMENT_FIELD from '@salesforce/schema/MessagingSession.qblmrt_Customer_Sentiment__c';
import STATUS_FIELD from '@salesforce/schema/MessagingSession.Status';
import invokePrompt from '@salesforce/apex/qblmrt_SentimentAnalysis.invokePrompt';

export default class Qblmrt_sentimentAnalysis extends LightningElement {
    @api recordId;
    @api cardTitle = 'Sentiment Analysis';
    @api cardIcon = 'custom:custom97';
    @api triggerType;
    promptResponse = {};
    isLoading = false;
    error;
    subscription = null;
    @track messagingSession;
    firstLoad = true;

    @wire(MessageContext)
    messageContext;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [CUSTOMER_SENTIMENT_FIELD, STATUS_FIELD],
    })
    wiredRecord({ error, data }) {
        if (error) {
            this.error = JSON.stringify(error);
        } else if (data) {
            this.error = null;
            this.messagingSession = data;
            if (this.firstLoad) {
                this.firstLoad = false;
                if (this.checkIfShouldInvokePromptOnLoad()) {
                    this.invokePrompt();
                }
            }
        }
    }

    checkIfShouldInvokePromptOnLoad() {
        return (
            (getFieldValue(this.messagingSession, CUSTOMER_SENTIMENT_FIELD) ===
                null ||
                getFieldValue(
                    this.messagingSession,
                    CUSTOMER_SENTIMENT_FIELD
                ) === undefined) &&
            (this.triggerType === 'Realtime' ||
                (this.triggerType === 'SessionEnds' &&
                    getFieldValue(this.messagingSession, STATUS_FIELD) ===
                        'Ended'))
        );
    }

    get sentiment() {
        return getFieldValue(this.messagingSession, CUSTOMER_SENTIMENT_FIELD);
    }

    get badgeTheme() {
        if (this.sentiment === 'positive') {
            return 'slds-badge slds-theme_success';
        }
        if (this.sentiment === 'negative') {
            return 'slds-badge slds-theme_error';
        }
        if (this.sentiment === 'neutral') {
            return 'slds-badge slds-badge_inverse';
        }
    }

    get sentimentIcon() {
        if (this.sentiment === 'positive') {
            return 'utility:smiley_and_people';
        }
        if (this.sentiment === 'negative') {
            return 'utility:sentiment_negative';
        }
        if (this.sentiment === 'neutral') {
            return 'utility:sentiment_neutral';
        }
    }

    get isTriggerTypeButton() {
        return this.triggerType === 'Button';
    }

    connectedCallback() {
        if (this.triggerType === 'Button') return;

        this.subscribeToMessageChannel();
    }

    subscribeToMessageChannel() {
        if (!this.subscription) {
            const messagingEvent =
                this.triggerType === 'Realtime'
                    ? ConversationEndUserChannel
                    : ConversationEndedChannel;
            this.subscription = subscribe(
                this.messageContext,
                messagingEvent,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    // Handler for message received by component
    handleMessage(message) {
        if (message.recordId === this.recordId) {
            this.invokePrompt();
        }
    }

    async invokePrompt() {
        if (this.isLoading) return;

        this.isLoading = true;
        let promptResponse;

        try {
            promptResponse = await invokePrompt({
                messagingSessionId: this.recordId,
            });
            promptResponse = JSON.parse(promptResponse);
            const recordInput = {
                fields: {
                    Id: this.recordId,
                    qblmrt_Customer_Sentiment__c: promptResponse.sentiment,
                },
            };

            await updateRecord(recordInput);
        } catch (e) {
            this.error = JSON.stringify(e);
        }
        this.isLoading = false;
    }
}