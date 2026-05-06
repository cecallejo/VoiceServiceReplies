import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateReplies from '@salesforce/apex/GroundedRepliesVoiceController.generateReplies';
import fetchTranscript from '@salesforce/apex/GroundedRepliesVoiceController.fetchTranscript';

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
    @api transcriptPollIntervalMs = 4000;
    @api debugMode = false;

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
    @track debugLogs = [];

    transcriptBuffer = '';
    wordCount = 0;
    processing = false;
    pollingInFlight = false;
    pollTimer;
    lastTranscriptSnapshot = '';
    lastEventTimestamp = 0;

    connectedCallback() {
        if (!this.requireStartButton) {
            this.listeningState = STATE_LISTENING;
            this.startPolling();
        }
        this.logDebug('Componente iniciado.');
    }

    disconnectedCallback() {
        this.stopPolling();
        this.logDebug('Componente finalizado.');
    }

    get showVoiceToolkit() {
        return this.recordId?.startsWith('0LQ');
    }

    get isListening() {
        return this.listeningState === STATE_LISTENING;
    }

    get actionLabel() {
        if (this.listeningState === STATE_NOT_STARTED) return 'Iniciar';
        if (!this.allowPause) return 'Parar';
        if (this.listeningState === STATE_LISTENING) return 'Pausar';
        return 'Retomar';
    }

    get showActionButton() {
        return this.allowPause || this.listeningState === STATE_NOT_STARTED || this.isListening;
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
            this.startPolling();
            this.logDebug('Monitoramento iniciado manualmente.');
            return;
        }
        if (!this.allowPause) {
            this.listeningState = STATE_NOT_STARTED;
            this.stopPolling();
            this.transcriptBuffer = '';
            this.wordCount = 0;
            this.lastTranscriptSnapshot = '';
            this.logDebug('Monitoramento parado manualmente.');
            return;
        }
        if (this.listeningState === STATE_LISTENING) {
            this.listeningState = STATE_PAUSED;
            this.stopPolling();
            this.logDebug('Monitoramento pausado.');
        } else {
            this.listeningState = STATE_LISTENING;
            this.startPolling();
            this.logDebug('Monitoramento retomado.');
        }
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
            this.lastTranscriptSnapshot = '';
            this.startPolling();
            this.logDebug(`Evento de chamada recebido: ${eventType}.`);
            return;
        }
        if (eventType === 'callended') {
            this.stopPolling();
            this.logDebug('Chamada encerrada. Polling interrompido.');
            return;
        }
        if (eventType !== 'transcript') return;
        if (!this.isListening) return;
        this.lastEventTimestamp = Date.now();
        this.logDebug('Evento de transcricao recebido via toolkit.');
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
        const shouldInclude = isCustomer || (this.trackCustomerSpeech && isAgent);
        if (!shouldInclude) return;

        const text = this.decodeHtmlEntities(rawText.trim());
        const words = this.countWords(text);
        this.transcriptBuffer += (this.transcriptBuffer ? ' ' : '') + text;
        this.wordCount += words;

        const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
        this.logDebug(`Delta por evento: +${words} palavras (contador ${this.wordCount}/${threshold}).`);
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
            this.logDebug(`Disparando recomendacoes (forcado=${force ? 'sim' : 'nao'}).`);
            const response = await generateReplies({
                voiceCallId: this.recordId,
                transcriptFlowName: this.transcriptFlowName,
                groundingFlowName: this.groundingFlowName
            });

            if (!response?.success) {
                this.errorMessage = response?.errorMessage || 'Nao foi possivel gerar recomendacoes.';
                this.logDebug(`Falha ao gerar recomendacoes: ${this.errorMessage}`);
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
                this.logDebug(`Recomendacoes geradas com sucesso: ${this.recommendations.length}.`);
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Erro inesperado.';
            this.logDebug(`Erro inesperado: ${this.errorMessage}`);
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
        return this.tokenizeWords(text).length;
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

    startPolling() {
        this.stopPolling();
        const interval = Number(this.transcriptPollIntervalMs) || 4000;
        this.pollTimer = window.setInterval(() => {
            this.pollTranscriptFallback();
        }, interval);
        this.logDebug(`Polling iniciado a cada ${interval}ms.`);
    }

    stopPolling() {
        if (this.pollTimer) {
            window.clearInterval(this.pollTimer);
            this.pollTimer = null;
            this.logDebug('Polling interrompido.');
        }
    }

    async pollTranscriptFallback() {
        if (!this.isListening || this.pollingInFlight || !this.recordId) return;

        const interval = Number(this.transcriptPollIntervalMs) || 4000;
        if (this.lastEventTimestamp && Date.now() - this.lastEventTimestamp < interval * 2) {
            return;
        }

        this.pollingInFlight = true;
        try {
            const latestTranscript = await fetchTranscript({
                voiceCallId: this.recordId,
                transcriptFlowName: this.transcriptFlowName
            });

            const current = this.extractRelevantPollingText(latestTranscript);
            if (!current) return;

            const previous = this.lastTranscriptSnapshot || '';
            if (current === previous) return;

            const delta = this.extractTranscriptDeltaByWords(previous, current);
            this.lastTranscriptSnapshot = current;
            if (!delta) return;

            const words = this.countWords(delta);
            if (words === 0) return;

            this.transcriptBuffer += (this.transcriptBuffer ? ' ' : '') + delta;
            this.wordCount += words;

            const threshold = Number(this.batchWordThreshold) || DEFAULT_BATCH_THRESHOLD;
            this.logDebug(`Delta por polling: +${words} palavras (contador ${this.wordCount}/${threshold}).`);
            if (this.wordCount >= threshold) {
                await this.requestRecommendations();
            }
        } catch (error) {
            console.warn('Erro no polling de transcricao:', error);
            this.logDebug('Erro no polling de transcricao.');
        } finally {
            this.pollingInFlight = false;
        }
    }

    normalizeTranscript(text) {
        return (text || '')
            .replace(/<br\s*\/?>/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    extractRelevantPollingText(rawTranscript) {
        const normalized = this.normalizeTranscript(rawTranscript);
        if (!normalized) return '';

        const lines = (rawTranscript || '')
            .replace(/<br\s*\/?>/gi, '\n')
            .split(/\r?\n/)
            .map((line) => line.trim())
            .filter((line) => line.length > 0);

        if (!lines.length) {
            return normalized;
        }

        const selected = [];
        lines.forEach((line) => {
            const cleanLine = this.normalizePollingLine(line);
            if (!cleanLine) return;

            const actorType = this.detectPollingActor(cleanLine);
            const isCustomerLine = actorType === 'customer';
            const isAgentLine = actorType === 'agent';

            if (isCustomerLine) {
                selected.push(cleanLine);
                return;
            }
            if (isAgentLine) {
                if (this.trackCustomerSpeech) selected.push(cleanLine);
                return;
            }
            if (this.trackCustomerSpeech) {
                selected.push(cleanLine);
            }
        });

        return this.normalizeTranscript(selected.join(' '));
    }

    normalizePollingLine(line) {
        return (line || '')
            .replace(/^conversationTranscript\s*\(/i, '')
            .replace(/\)\s*$/i, '')
            .replace(/^\(\s*\d+\s*[smh](?:\s+\d+\s*[smh])?\s*\)\s*/i, '')
            .replace(/^\[?\d{1,2}:\d{2}(?::\d{2})?\]?\s*/i, '')
            .replace(/^\[?\d{4}-\d{2}-\d{2}[^\]]*\]?\s*/i, '')
            .trim();
    }

    detectPollingActor(cleanLine) {
        const actorMatch = cleanLine.match(/^([a-zA-Z_][a-zA-Z0-9_\s-]{0,30})\s*[:\-]/);
        if (!actorMatch) return 'unknown';
        const actor = (actorMatch[1] || '').toLowerCase().replace(/\s+/g, '');

        if (
            actor === 'enduser' ||
            actor === 'end_user' ||
            actor === 'customer' ||
            actor === 'cliente' ||
            actor === 'caller' ||
            actor === 'participant' ||
            actor === 'usuario' ||
            actor === 'consumidor'
        ) {
            return 'customer';
        }

        if (
            actor === 'agent' ||
            actor === 'agente' ||
            actor === 'servicerep' ||
            actor === 'atendente' ||
            actor === 'representante' ||
            actor === 'advisor'
        ) {
            return 'agent';
        }

        return 'unknown';
    }

    extractTranscriptDeltaByWords(previous, current) {
        if (!previous) return current;
        const prevWords = this.tokenizeWords(previous);
        const currWords = this.tokenizeWords(current);
        if (!currWords.length) return '';

        const maxOverlap = Math.min(prevWords.length, currWords.length);
        let overlap = 0;
        for (let size = maxOverlap; size > 0; size--) {
            let match = true;
            for (let i = 0; i < size; i++) {
                if (prevWords[prevWords.length - size + i] !== currWords[i]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                overlap = size;
                break;
            }
        }

        const deltaWords = currWords.slice(overlap);
        return deltaWords.join(' ').trim();
    }

    tokenizeWords(text) {
        return (text || '')
            .toLowerCase()
            .replace(/[^a-z0-9À-ÖØ-öø-ÿ\s'-]/gi, ' ')
            .split(/\s+/)
            .filter((word) => word.length > 0);
    }

    get showDebugPanel() {
        return this.debugMode;
    }

    logDebug(message) {
        if (!this.debugMode || !message) return;
        const now = new Date().toLocaleTimeString('pt-BR');
        const line = `[${now}] ${message}`;
        this.debugLogs = [line, ...this.debugLogs].slice(0, 30);
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
