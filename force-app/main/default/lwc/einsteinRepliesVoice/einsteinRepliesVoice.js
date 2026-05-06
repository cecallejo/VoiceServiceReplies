import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import ConversationEndUserChannel from '@salesforce/messageChannel/lightning__conversationEndUserMessage';
import getSuggestions from '@salesforce/apex/EinsteinRepliesVoiceService.getSuggestions';

export default class EinsteinRepliesVoice extends LightningElement {
    @api recordId;
    @api groundedPromptTemplate;
    @api contextPromptTemplate;
    @api cardTitle = 'Einstein Replies Voice';
    @api cardIcon = 'utility:lightbulb';

    @track groundedRecommendations = [];
    @track contextRecommendations = [];

    isLoading = false;
    error;
    subscription;
    pendingRefresh = false;
    debounceTimer;

    @wire(MessageContext)
    messageContext;

    get hasRecommendations() {
        return this.groundedRecommendations.length > 0 || this.contextRecommendations.length > 0;
    }

    get hasConfig() {
        return Boolean(this.groundedPromptTemplate || this.contextPromptTemplate);
    }

    connectedCallback() {
        this.subscribeToMessages();
        this.refreshSuggestions();
    }

    disconnectedCallback() {
        this.unsubscribeFromMessages();
        if (this.debounceTimer) {
            window.clearTimeout(this.debounceTimer);
        }
    }

    subscribeToMessages() {
        if (this.subscription) {
            return;
        }

        this.subscription = subscribe(
            this.messageContext,
            ConversationEndUserChannel,
            (message) => this.handleConversationMessage(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    unsubscribeFromMessages() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
    }

    handleConversationMessage(message) {
        if (!message || message.recordId !== this.recordId) {
            return;
        }

        if (this.debounceTimer) {
            window.clearTimeout(this.debounceTimer);
        }
        this.debounceTimer = window.setTimeout(() => {
            this.refreshSuggestions();
        }, 500);
    }

    async refreshSuggestions() {
        if (!this.recordId || !this.hasConfig) {
            return;
        }

        if (this.isLoading) {
            this.pendingRefresh = true;
            return;
        }

        this.isLoading = true;
        this.error = null;

        try {
            const response = await getSuggestions({
                voiceCallId: this.recordId,
                groundedPromptTemplate: this.groundedPromptTemplate,
                contextPromptTemplate: this.contextPromptTemplate
            });

            this.groundedRecommendations = this.normalizeSuggestions(
                response?.groundedRecommendations,
                'Grounded'
            );
            this.contextRecommendations = this.normalizeSuggestions(
                response?.contextRecommendations,
                'Context'
            );
            this.error = response?.errorMessage;
        } catch (e) {
            this.error = this.normalizeError(e);
        } finally {
            this.isLoading = false;
            if (this.pendingRefresh) {
                this.pendingRefresh = false;
                this.refreshSuggestions();
            }
        }
    }

    normalizeSuggestions(items, fallbackSource) {
        if (!Array.isArray(items)) {
            return [];
        }

        return items
            .filter((item) => item && item.text)
            .map((item, index) => ({
                id: `${fallbackSource}-${index}`,
                text: item.text,
                source: item.source || fallbackSource,
                articleTitle: item.articleTitle,
                articleId: item.articleId
            }));
    }

    normalizeError(error) {
        return error?.body?.message || error?.message || 'Erro ao gerar recomendações.';
    }
}
