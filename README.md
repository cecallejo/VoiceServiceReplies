# Voice Service Replies

Componente reutilizavel para recomendacoes de resposta em tempo real em `VoiceCall`, com foco em grounding por Knowledge e resiliencia para diferentes providers de voz (event-driven + polling fallback).

## O que este projeto entrega

- LWC `groundedRepliesVoiceMonitor` para exibir recomendacoes no layout de `VoiceCall`.
- Controle de estado de monitoramento (iniciar, pausar/retomar ou parar, conforme configuracao).
- Contador de palavras por delta de transcricao.
- Fallback por polling de transcricao quando eventos em tempo real nao chegam.
- Integracao com Prompt Template via Flows.
- Search query contextual para grounding (ultimo bloco de falas do EndUser).
- Logging separado entre debug visual no card e `System.debug` no Apex.
- Coleta de feedback no card (`thumbs up/down`) com motivos para feedback negativo.

## Arquitetura

### Componentes principais

- `force-app/main/default/lwc/groundedRepliesVoiceMonitor`
  - UI, estado e logica de monitoramento/transcricao.
- `force-app/main/default/classes/GroundedRepliesVoiceController.cls`
  - Orquestracao Apex para buscar transcricao e gerar recomendacoes.
- `force-app/main/default/flows/Get_Voice_Call_Transcript.flow-meta.xml`
  - Wrapper do `getConvTscpForRecord` para retornar `transcriptText`.
- `force-app/main/default/flows/Voice_Grounded_Replies_Bridge.flow-meta.xml`
  - Bridge para executar Prompt Template e retornar `promptResponse`.
- `force-app/main/default/genAiPromptTemplates/Grounded_Service_Reply_Voice_Monitor.genAiPromptTemplate-meta.xml`
  - Prompt grounded com retorno estruturado em JSON.
- `force-app/main/default/genAiPromptTemplates/OnCall_Sentiment_Analysis.genAiPromptTemplate-meta.xml`
  - Prompt de analise de sentimento do cliente (`positivo|neutro|negativo`).

### Fluxo em runtime

1. O LWC recebe eventos de voz (`lightning-service-cloud-voice-toolkit-api`) quando disponiveis.
2. Em paralelo, roda polling configuravel (`transcriptPollIntervalMs`) via `Get_Voice_Call_Transcript`.
3. O texto novo (delta) e contabilizado internamente.
4. Ao atingir `batchWordThreshold`, o LWC chama Apex.
5. Apex executa:
   - `Get_Voice_Call_Transcript` para transcricao atual.
   - calculo de `SearchQuery` com base no trecho relevante do EndUser.
   - `Voice_Grounded_Replies_Bridge` para gerar resposta grounded.
6. O LWC renderiza recomendacoes, links de Knowledge e feedback (`thumbs up/down`).
7. Em paralelo, o Apex executa o prompt de sentimento (`OnCall_Sentiment_Analysis`).

## Configuracao no App Builder (VoiceCall)

Adicione o componente **Grounded Replies Voice Monitor** na pagina de registro de `VoiceCall`.

Propriedades principais:

- `Card Title`: titulo do card.
- `Allow Pause/Resume`: habilita modo pausar/retomar.
- `Require Start Button`: exige clique em iniciar.
- `Include Service Rep Messages`: inclui falas do agente humano.
- `Word Batch Threshold`: gatilho interno de palavras para gerar recomendacoes (exibido apenas na barra de progresso visual).
- `Transcript Poll Interval (ms)`: intervalo de polling da transcricao.
- `Modo de depuracao`: mostra painel de logs no card.
- `Apex Log Mode`: habilita logs de servidor via `System.debug` (independente do debug visual).
- `Transcript Flow Name`: default `Get_Voice_Call_Transcript`.
- `Grounding Flow Name`: default `Voice_Grounded_Replies_Bridge`.
- `Sentiment Prompt Name`: default `OnCall_Sentiment_Analysis`.

Comportamento do botao:

- `Allow Pause/Resume = true`: `Iniciar` -> `Pausar` -> `Retomar`.
- `Allow Pause/Resume = false`: `Iniciar` -> `Parar`.

## Contrato do Prompt (JSON esperado)

O parser espera o formato:

```json
{
  "responses": [
    {
      "response1": "<answer 1>",
      "source": {
        "sourceRecordId": "<value related to fieldApiKey SourceRecordId__c; must start with ka0>",
        "dataSourceObject": "<dataSourceObject>"
      }
    },
    {
      "response2": "<answer 2>",
      "source": {
        "sourceRecordId": "<value related to fieldApiKey SourceRecordId__c; must start with ka0>",
        "dataSourceObject": "<dataSourceObject>"
      }
    }
  ]
}
```

Compatibilidade: o parser tambem aceita `response` (legado) em cada item de `responses[]`.

## Dependencias e prerequisitos

- Salesforce org com Service Cloud Voice habilitado.
- Prompt Builder / Einstein features necessarias habilitadas.
- Flow `Get_Voice_Call_Transcript` ativo.
- Flow `Voice_Grounded_Replies_Bridge` ativo.
- Prompt Template `Grounded_Service_Reply_Voice_Monitor` publicado e com versao ativa.
- Prompt Template `OnCall_Sentiment_Analysis` publicado e com versao ativa.

## Configuracao detalhada de Flow e Prompts

Esta secao e a referencia para quando voce precisar ajustar o Flow e/ou os Prompts sem quebrar o funcionamento do pacote.

### 1) Contrato entre Flow e Prompts (obrigatorio)

O componente e o Apex assumem o seguinte contrato:

- Flow de grounding: `Voice_Grounded_Replies_Bridge`
- Prompt Template: `Grounded_Service_Reply_Voice_Monitor`
- Prompt Template de sentimento: `OnCall_Sentiment_Analysis`
- Input do prompt no Flow: `Input:Transcript`
- Novo input do Flow de grounding: `SearchQuery` (alem de `transcript` completo).
- Output do Flow para Apex/LWC: variavel `promptResponse` (String, output=true)

Se qualquer um desses nomes mudar, ajuste tambem:

- Propriedade do LWC no App Builder: `Grounding Flow Name`
- Parser/consumidor do retorno no Apex e no LWC

### 2) Como configurar o Flow `Voice_Grounded_Replies_Bridge`

No Flow Builder (Autolaunched Flow):

1. Crie/edite a variavel de entrada `transcript`:
   - Tipo: Text
   - Available for input: true
2. Crie/edite a variavel de entrada `SearchQuery`:
   - Tipo: Text
   - Available for input: true
3. Crie/edite a variavel de saida `promptResponse`:
   - Tipo: Text
   - Available for output: true
4. Adicione uma acao de Prompt Template com:
   - Prompt: `Grounded_Service_Reply_Voice_Monitor`
   - Parametro de entrada: `Input:Transcript` = `{!transcript}`
   - Parametro de entrada para busca: mapeie para `{!SearchQuery}` conforme ajuste do prompt/flow.
   - Parametro de saida: `promptResponse` -> `{!promptResponse}`
5. Garanta que o Start aponta para essa acao.
6. Salve e ative (status Active).

Checklist de validacao do Flow:

- O nome API do Flow e `Voice_Grounded_Replies_Bridge`.
- O elemento de acao referencia o prompt correto.
- A variavel `SearchQuery` existe e esta conectada ao mapeamento do prompt.
- A variavel `promptResponse` esta marcada como output.
- O Flow esta ativo na org destino.

### 3) Como configurar os Prompts

No Prompt Builder:

1. Confirme o nome API do template: `Grounded_Service_Reply_Voice_Monitor`.
2. Confirme a entrada:
   - `Transcript`
   - referencia `Input:Transcript`
   - Required = true
3. Confirme o Data Provider de grounding (Einstein Search Retriever) ativo na org.
4. Garanta que o conteudo do prompt instrui retorno em JSON no formato esperado.
5. Publique uma versao e deixe essa versao como ativa.

Checklist de validacao dos Prompts:

- Existe versao `Published`.
- O template tem `activeVersionIdentifier` valido.
- O input `Input:Transcript` existe e e obrigatorio.
- O prompt/flow de grounding ja considera `SearchQuery` como trecho de busca.
- O JSON de resposta segue o contrato em "Contrato do Prompt (JSON esperado)".
- No prompt `OnCall_Sentiment_Analysis`, o retorno contem `{"sentiment":"positivo|neutro|negativo"}`.

### 3.1) Regra de composicao do `SearchQuery`

O Apex envia ao Flow de grounding:

- `transcript`: transcricao completa da chamada (mantida para contexto total).
- `SearchQuery`: sempre o ultimo bloco continuo de falas do `EndUser`, mesmo quando as ultimas mensagens da transcricao sao do agente.

Se a transcricao nao vier com marcacao de ator reconhecivel, o fallback e usar o texto normalizado disponivel.

### 3.2) Referencia da org `wallace` (versao atual)

#### Flow bridge ativo

- Flow: `Voice_Grounded_Replies_Bridge` (`force-app/main/default/flows/Voice_Grounded_Replies_Bridge.flow-meta.xml`)
- Tipo: `AutoLaunchedFlow`
- Status: `Active`
- Prompt chamado na acao `Get_Grounded_Recommendation`: `Grounded_Service_Reply_Voice_Monitor`
- Log no objeto customizado: `Voice_Service_Reply__c` (elemento `Registra_log`)

Campos preenchidos no log pelo flow:

- `Voice_Call__c` <- `recordId`
- `Search_Query__c` <- `SearchQuery`
- `Answer_1__c` <- formula `Response1`
- `Answer_2__c` <- formula `Response2`

#### Objeto customizado de log usado no bridge

- Objeto: `Voice_Service_Reply__c`
- Label: `Voice Service Reply`
- Finalidade: persistir o log de entrada e saidas do bridge de grounding por chamada de voz

Campos do objeto:

- `Voice_Call__c`: Lookup para `VoiceCall`
- `Search_Query__c`: Long Text Area (2000)
- `Answer_1__c`: Long Text Area (1000)
- `Answer_2__c`: Long Text Area (1000)
- `Feedback_Status__c`: Picklist (`UP` | `DOWN`)
- `Feedback_Reasons__c`: Long Text Area (1000)
- `Feedback_At__c`: DateTime
- `Feedback_By__c`: Lookup para `User`

#### Prompt de referencia (ultima versao `wallace`)

Arquivo de metadata: `package-src/main/default/genAiPromptTemplates/Post_Call_Voice_Sentiment_Analysis.genAiPromptTemplate-meta.xml`

Conteudo da versao atual:

```text
Voce e um classificador de sentimento para atendimento por voz.
Analise a transcricao da conversa entre cliente e atendente e classifique APENAS o sentimento do cliente.

Categorias permitidas:
- positivo
- neutro
- negativo

Regras obrigatorias:
1) Retorne exatamente um objeto JSON valido.
2) Nao inclua texto fora do JSON.
3) Use este formato:
{
  "sentiment": "<positivo|neutro|negativo>"
}

Considere o contexto geral da conversa e priorize os trechos falados pelo cliente.

TRANSCRICAO:
{!$Input:Transcript}
```

### 4) Ordem correta de implantacao (essencial)

Para evitar erro de dependencia em org destino:

1. Instale o pacote promovido (04t).
2. Deploy complementar de Flow + Prompts (`manifest/post-install-package.xml`).
3. Confirme Flow ativo e Prompts publicados/ativos.
4. So depois valide a execucao no LWC.

Comando recomendado:

```bash
./scripts/install_full_asset.sh <alias-org-destino>
```

### 5) Ajustes comuns e impacto

- Alterar nome do Flow:
  - atualizar App Builder (`Grounding Flow Name`) e qualquer referencia em metadata/script.
- Alterar nome da entrada do Prompt:
  - atualizar mapeamento da acao no Flow (`Input:Transcript`).
- Alterar schema do JSON de resposta:
  - atualizar parser no Apex/LWC antes de publicar em producao.
- Alterar retriever de grounding:
  - validar se a org destino possui o novo retriever com mesmo comportamento.

## Instalacao rapida por metadata deploy

```bash
sf org login web --alias minha-org
sf project deploy start --target-org minha-org --source-dir force-app
```

## Empacotamento para reuso em outras orgs

Use o guia completo em `docs/PACKAGING.md`.

## Instalacao completa (pacote + complemento)

Para instalar tudo em uma org destino (pacote promovido + flows + prompt):

```bash
./scripts/install_full_asset.sh <alias-org-destino>
```

URL direta do instalador do pacote (LWC + Apex):

- Producao/Developer Edition: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd16IAC`
- Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd16IAC`

Observacao: essa URL instala o pacote base (componentes como LWC e Apex). Para instalar tambem os metadados complementares (Flows + Prompts), execute o script acima ou faça o deploy do `manifest/post-install-package.xml`.

Esse script executa:

- instalacao da versao promovida do pacote;
- deploy complementar de:
  - `Get_Voice_Call_Transcript` (Flow)
  - `Voice_Grounded_Replies_Bridge` (Flow)
  - `Grounded_Service_Reply_Voice_Monitor` (Prompt Template)
  - `OnCall_Sentiment_Analysis` (Prompt Template)
  - `Post_Call_Voice_Sentiment_Analysis` (Prompt Template)
  - `Voice_Service_Reply__c` (Custom Object de log do bridge)
- validacao basica dos FlowDefinitions implantados.

## Troubleshooting rapido

- Contador nao sobe:
  - Verifique se `Require Start Button` exige iniciar manual.
  - Ative `Modo de depuracao` para inspecionar eventos/polling.
- Contador sobe com ator errado:
  - Revise `Include Service Rep Messages`.
  - Valide formato da transcricao no provider.
- Sem recomendacoes:
  - Verifique se ambos os flows estao ativos.
  - Valide se o prompt esta publicado e com versao ativa.

## Observabilidade e logs (UI + Apex)

### Debug visual no componente (LWC)

- Controle: `Modo de depuracao`.
- Mostra no card:
  - eventos de transcricao/polling;
  - transcricao completa enviada ao grounding;
  - `SearchQuery` enviada ao grounding.

### Log de servidor no Apex (`System.debug`)

- Controle: `Apex Log Mode` (separado do `Modo de depuracao`).
- Quando habilitado, registra a cada nova busca de recomendacao:
  - `Grounding transcript completo: ...`
  - `Grounding SearchQuery: ...`
  - `Grounding recomendacoes: ...` (JSON serializado)

### Como visualizar o log Apex (Setup)

1. Setup -> Debug Logs -> adicione seu usuario em `Monitored Users`.
2. Deixe `Apex Log Mode = true` no componente.
3. Gere nova recomendacao no card.
4. Abra o log recente e busque pelas 3 chaves acima.

### Como visualizar via CLI

```bash
sf apex log list --target-org <alias>
sf apex log get --log-id <LOG_ID> --target-org <alias>
```
