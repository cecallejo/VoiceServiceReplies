import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateReplies from '@salesforce/apex/GroundedRepliesVoiceController.generateReplies';

const STATE_NOT_STARTED = 'not_started';
const STATE_LISTENING = 'listening';
const STATE_PAUSED = 'paused';
const DEFAULT_BATCH_THRESHOLD = 50;

export default class GroundedRepliesVoiceMonitor extends LightningElement {
    @api recordId;
    @api cardTitle = 'Recomendacoes de respostas';
    @api cardIcon = 'utility:lightbulb';
    @api componentHeight = 400;
    @api batchWordThreshold = DEFAULT_BATCH_THRESHOLD;
    @api trackCustomerSpeech = false;
    @api transcriptFlowName = 'Get_Voice_Call_Transcript';
    @api groundingFlowName = 'Voice_Grounded_Replies_Bridge';

    _allowPause;
    _requireStartButton;
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

    @track listeningState = STATE_NOT_STARTED;
    @track recommendations = [];
    @track isLoading = false;
    @track errorMessage;
    @track lastTranscriptPreview;

    transcriptBuffer = '';
    wordCount = 0;
    processing = false;

    connectedCallback() {
        if (!this.requireStartButton) {
            this.listeningState = STATE_LISTENING;
        }
    }

    get showVoiceToolkit() {
        return this.recordId?.startsWith('0LQ');
    }

    get isListening() {
        return this.listeningState === STATE_LISTENING;
    }

    get canPause() {
        return this.allowPause && this.listeningState !== STATE_NOT_STARTED;
    }

    get actionLabel() {
        if (this.listeningState === STATE_NOT_STARTED) return 'Iniciar';
        if (this.listeningState === STATE_LISTENING) return 'Pausar';
        return 'Retomar';
    }

    get estadoLabel() {
        if (this.listeningState === STATE_NOT_STARTED) return 'Nao iniciado';
        if (this.listeningState === STATE_LISTENING) return 'Iniciado';
        return 'Pausado';
    }

    get estadoClasse() {
        if (this.listeningState === STATE_NOT_STARTED) return 'semaforo vermelho';
        if (this.listeningState === STATE_LISTENING) return 'semaforo verde';
        return 'semaforo amarelo';
    }

    get progressoPercentual() {
        const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
        if (!threshold) return 0;
        return Math.min(Math.round((this.wordCount / threshold) * 100), 100);
    }

    get progressoStyle() {
        return `width:${this.progressoPercentual}%;`;
    }

    get wordCounter() {
        const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
        return `${this.wordCount}/${threshold}`;
    }

    handleActionClick() {
        if (this.listeningState === STATE_NOT_STARTED) {
            this.listeningState = STATE_LISTENING;
            return;
        }
        if (!this.allowPause) return;
        this.listeningState =
            this.listeningState === STATE_LISTENING ? STATE_PAUSED : STATE_LISTENING;
    }

    handleVoiceConversationEvent(event) {
        if (!event || !event.type || !event.detail) return;
        const eventType = event.type.toLowerCase().replace(/^on/i, '');
        const detail = event.detail?.data ? event.detail.data : event.detail;
        if (eventType === 'callstarted' || eventType === 'callconnected') {
            if (!this.requireStartButton && this.listeningState === STATE_NOT_STARTED) {
                this.listeningState = STATE_LISTENING;
            }
            this.transcriptBuffer = '';
            this.wordCount = 0;
            return;
        }
        if (eventType !== 'transcript') return;
        if (!this.isListening) return;
        this.handleTranscript(detail);
    }

    handleTranscript(detail) {
        if (!detail) return;
        const actorType = this.extractActorType(detail);
        const rawText = this.extractTranscriptText(detail);
        if (!rawText || !rawText.trim()) return;

        const actor = (actorType || '').toLowerCase();
        const isAgent = actor === 'agent' || actor === 'service_rep' || actor === 'servicerep';
        const isCustomer =
            actor === 'enduser' ||
            actor === 'end_user' ||
            actor === 'customer' ||
            actor === 'caller' ||
            actor === 'participant' ||
            actor === '';
        // Default behavior: always monitor customer messages.
        // Service rep messages are included only when configured.
        const shouldInclude =
            isCustomer || (this.trackCustomerSpeech && isAgent);
        if (!shouldInclude) return;

        const text = this.decodeHtmlEntities(rawText.trim());
        const words = this.countWords(text);
        this.transcriptBuffer += (this.transcriptBuffer ? ' ' : '') + text;
        this.wordCount += words;

        const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
        if (this.wordCount >= threshold) {
            this.requestRecommendations();
        }
    }

    async handleManualRefresh() {
        await this.requestRecommendations(true);
    }

    async requestRecommendations(force = false) {
        if (this.processing || this.isLoading) return;
        if (!force && !this.transcriptBuffer.trim()) return;

        this.processing = true;
        this.isLoading = true;
        this.errorMessage = null;

        try {
            const response = await generateReplies({
                voiceCallId: this.recordId,
                transcriptFlowName: this.transcriptFlowName,
                groundingFlowName: this.groundingFlowName
            });

            if (!response?.success) {
                this.errorMessage = response?.errorMessage || 'Nao foi possivel gerar recomendacoes.';
            } else {
                this.recommendations = (response.recommendations || []).map((item, index) => ({
                    ...item,
                    rowKey: `${item.sourceRecordId || 'no-source'}-${index}`,
                    knowledgeTooltip: item.articleTitle
                        ? `Artigo: ${item.articleTitle}`
                        : item.sourceRecordId
                            ? `Artigo: ${item.sourceRecordId}`
                            : 'Sem artigo vinculado',
                    isKnowledgeLinkable: item.sourceRecordId?.startsWith('ka0'),
                    disableKnowledgeButton: !item.sourceRecordId?.startsWith('ka0')
                }));
                this.lastTranscriptPreview = (response.transcript || '').substring(0, 300);
                this.transcriptBuffer = '';
                this.wordCount = 0;
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Erro inesperado.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Erro',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
            this.processing = false;
        }
    }

    countWords(text) {
        return text ? text.split(/\s+/).filter((word) => word.length > 0).length : 0;
    }

    decodeHtmlEntities(text) {
        if (!text) return text;
        const txt = document.createElement('textarea');
        txt.innerHTML = text;
        return txt.value;
    }

    extractActorType(detail) {
        return (
            detail.actorType ||
            detail.ActorType ||
            (detail.sender ? detail.sender.actorType || detail.sender.role || detail.sender.type : null) ||
            (detail.speaker ? detail.speaker.role || detail.speaker.type : null) ||
            detail.speakerType ||
            detail.participantType ||
            null
        );
    }

    extractTranscriptText(detail) {
        if (detail.content?.text) return detail.content.text;
        if (typeof detail.content === 'string') return detail.content;
        return (
            detail.message ||
            detail.Message ||
            detail.transcript ||
            detail.transcriptText ||
            detail.textSegment ||
            detail.payload?.text ||
            detail.text ||
            null
        );
    }

    handleVoiceToolkitError() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Erro de voz',
                message: 'Falha ao receber eventos de transcricao da ligacao.',
                variant: 'warning'
            })
        );
    }

    handleKnowledgeClick(event) {
        const articleId = event.currentTarget?.dataset?.articleId;
        if (!articleId || !articleId.startsWith('ka0')) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Base de conhecimento',
                    message: 'Nao foi possivel abrir o artigo para esta recomendacao.',
                    variant: 'warning'
                })
            );
            return;
        }

        window.open(`/lightning/r/Knowledge__kav/${articleId}/view`, '_blank');
    }
}
