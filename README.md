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

## Instalacao rapida por metadata deploy

```bash
sf org login web --alias minha-org
sf project deploy start --target-org minha-org --source-dir force-app
```

## Empacotamento para reuso em outras orgs

Use o guia completo em `docs/PACKAGING.md`.

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
