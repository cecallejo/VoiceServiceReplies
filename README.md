# Voice Service Replies

Componente reutilizavel para recomendacoes de resposta em tempo real em `VoiceCall`, com foco em grounding por Knowledge e resiliencia para diferentes providers de voz (event-driven + polling fallback).

## O que este projeto entrega

- LWC `groundedRepliesVoiceMonitor` para exibir recomendacoes no layout de `VoiceCall`.
- Controle de estado de monitoramento (iniciar, pausar/retomar ou parar, conforme configuracao).
- Contador de palavras por delta de transcricao.
- Fallback por polling de transcricao quando eventos em tempo real nao chegam.
- Integracao com Prompt Template via Flows.

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

### Fluxo em runtime

1. O LWC recebe eventos de voz (`lightning-service-cloud-voice-toolkit-api`) quando disponiveis.
2. Em paralelo, roda polling configuravel (`transcriptPollIntervalMs`) via `Get_Voice_Call_Transcript`.
3. O texto novo (delta) e contabilizado no contador.
4. Ao atingir `batchWordThreshold`, o LWC chama Apex.
5. Apex executa:
   - `Get_Voice_Call_Transcript` para transcricao atual.
   - `Voice_Grounded_Replies_Bridge` para gerar resposta grounded.
6. O LWC renderiza recomendacoes e links de Knowledge.

## Configuracao no App Builder (VoiceCall)

Adicione o componente **Grounded Replies Voice Monitor** na pagina de registro de `VoiceCall`.

Propriedades principais:

- `Card Title`: titulo do card.
- `Allow Pause/Resume`: habilita modo pausar/retomar.
- `Require Start Button`: exige clique em iniciar.
- `Include Service Rep Messages`: inclui falas do agente humano.
- `Word Batch Threshold`: gatilho de palavras para gerar recomendacoes.
- `Transcript Poll Interval (ms)`: intervalo de polling da transcricao.
- `Modo de depuracao`: mostra painel de logs no card.
- `Transcript Flow Name`: default `Get_Voice_Call_Transcript`.
- `Grounding Flow Name`: default `Voice_Grounded_Replies_Bridge`.

Comportamento do botao:

- `Allow Pause/Resume = true`: `Iniciar` -> `Pausar` -> `Retomar`.
- `Allow Pause/Resume = false`: `Iniciar` -> `Parar`.

## Contrato do Prompt (JSON esperado)

O parser espera o formato:

```json
{
  "responses": [
    {
      "response": "<answer 1>",
      "source": {
        "sourceRecordId": "<sourceRecordId>",
        "dataSourceObject": "<dataSourceObject>"
      }
    },
    {
      "response": "<answer 2>",
      "source": {
        "sourceRecordId": "<sourceRecordId>",
        "dataSourceObject": "<dataSourceObject>"
      }
    }
  ]
}
```

## Dependencias e prerequisitos

- Salesforce org com Service Cloud Voice habilitado.
- Prompt Builder / Einstein features necessarias habilitadas.
- Flow `Get_Voice_Call_Transcript` ativo.
- Flow `Voice_Grounded_Replies_Bridge` ativo.
- Prompt Template `Grounded_Service_Reply_Voice_Monitor` publicado e com versao ativa.

## Configuracao detalhada de Flow e Prompt

Esta secao e a referencia para quando voce precisar ajustar o Flow e/ou o Prompt sem quebrar o funcionamento do pacote.

### 1) Contrato entre Flow e Prompt (obrigatorio)

O componente e o Apex assumem o seguinte contrato:

- Flow de grounding: `Voice_Grounded_Replies_Bridge`
- Prompt Template: `Grounded_Service_Reply_Voice_Monitor`
- Input do prompt no Flow: `Input:Transcript`
- Output do Flow para Apex/LWC: variavel `promptResponse` (String, output=true)

Se qualquer um desses nomes mudar, ajuste tambem:

- Propriedade do LWC no App Builder: `Grounding Flow Name`
- Parser/consumidor do retorno no Apex e no LWC

### 2) Como configurar o Flow `Voice_Grounded_Replies_Bridge`

No Flow Builder (Autolaunched Flow):

1. Crie/edite a variavel de entrada `transcript`:
   - Tipo: Text
   - Available for input: true
2. Crie/edite a variavel de saida `promptResponse`:
   - Tipo: Text
   - Available for output: true
3. Adicione uma acao de Prompt Template com:
   - Prompt: `Grounded_Service_Reply_Voice_Monitor`
   - Parametro de entrada: `Input:Transcript` = `{!transcript}`
   - Parametro de saida: `promptResponse` -> `{!promptResponse}`
4. Garanta que o Start aponta para essa acao.
5. Salve e ative (status Active).

Checklist de validacao do Flow:

- O nome API do Flow e `Voice_Grounded_Replies_Bridge`.
- O elemento de acao referencia o prompt correto.
- A variavel `promptResponse` esta marcada como output.
- O Flow esta ativo na org destino.

### 3) Como configurar o Prompt `Grounded_Service_Reply_Voice_Monitor`

No Prompt Builder:

1. Confirme o nome API do template: `Grounded_Service_Reply_Voice_Monitor`.
2. Confirme a entrada:
   - `Transcript`
   - referencia `Input:Transcript`
   - Required = true
3. Confirme o Data Provider de grounding (Einstein Search Retriever) ativo na org.
4. Garanta que o conteudo do prompt instrui retorno em JSON no formato esperado.
5. Publique uma versao e deixe essa versao como ativa.

Checklist de validacao do Prompt:

- Existe versao `Published`.
- O template tem `activeVersionIdentifier` valido.
- O input `Input:Transcript` existe e e obrigatorio.
- O JSON de resposta segue o contrato em "Contrato do Prompt (JSON esperado)".

### 4) Ordem correta de implantacao (essencial)

Para evitar erro de dependencia em org destino:

1. Instale o pacote promovido (04t).
2. Deploy complementar de Flow + Prompt (`manifest/post-install-package.xml`).
3. Confirme Flow ativo e Prompt publicado/ativo.
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

Observacao: essa URL instala o pacote base (componentes como LWC e Apex). Para instalar tambem os metadados complementares (Flows + Prompt), execute o script acima ou faça o deploy do `manifest/post-install-package.xml`.

Esse script executa:

- instalacao da versao promovida do pacote;
- deploy complementar de:
  - `Get_Voice_Call_Transcript` (Flow)
  - `Voice_Grounded_Replies_Bridge` (Flow)
  - `Grounded_Service_Reply_Voice_Monitor` (Prompt Template)
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
