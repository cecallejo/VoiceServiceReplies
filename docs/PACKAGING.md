# Empacotamento e distribuicao

Este guia descreve como criar um **Unlocked Package** para instalar o asset em outras orgs Salesforce.

## 1) Pre-requisitos

- Dev Hub habilitado.
- Salesforce CLI autenticado no Dev Hub.
- Permissoes para criar pacotes no Dev Hub.

```bash
sf org login web --set-default-dev-hub --alias meu-devhub
```

## 2) Criar pacote (uma unica vez)

```bash
sf package create \
  --name "Voice Service Replies" \
  --package-type Unlocked \
  --path force-app \
  --target-dev-hub meu-devhub
```

Depois disso, copie o `0Ho...` retornado e adicione no `sfdx-project.json` em `packageAliases`.

Exemplo:

```json
"packageAliases": {
  "VoiceServiceReplies": "0HoXXXXXXXXXXXX"
}
```

## 3) Gerar versao instalavel

```bash
sf package version create \
  --package VoiceServiceReplies \
  --installation-key-bypass \
  --wait 30 \
  --target-dev-hub meu-devhub
```

No final, voce recebera:

- `Subscriber Package Version Id` (`04t...`) -> usado para instalar.
- `Package Version Id` (`05i...`) -> identificador da versao no Dev Hub.

## 4) Promover versao (opcional, recomendado)

```bash
sf package version promote \
  --package 04tXXXXXXXXXXXX \
  --target-dev-hub meu-devhub \
  --no-prompt
```

## 5) Instalar em outra org

```bash
sf org login web --alias org-destino
sf package install \
  --package 04tXXXXXXXXXXXX \
  --target-org org-destino \
  --wait 30 \
  --publish-wait 10 \
  --no-prompt
```

Opcao via URL do instalador (pacote base com LWC + Apex):

- Producao/Developer Edition: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd0wIAC`
- Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd0wIAC`

> Importante: a URL instala apenas o pacote base. Para completar a instalacao (Flows + Prompt), rode o deploy complementar via `manifest/post-install-package.xml` ou use `./scripts/install_full_asset.sh <alias-org-destino>`.

## 6) Pos-instalacao

Na org destino:

- Verifique se os flows estao ativos:
  - `Get_Voice_Call_Transcript`
  - `Voice_Grounded_Replies_Bridge`
- Verifique se o Prompt Template `Grounded_Service_Reply_Voice_Monitor` esta publicado e ativo.
- Adicione `Grounded Replies Voice Monitor` na Lightning Record Page de `VoiceCall`.
- Ajuste propriedades do componente conforme necessidade.

### Guia detalhado: configurar Flow + Prompt na org destino

Use este guia quando houver ajustes de comportamento entre versoes, ou quando o template/flow precisar ser recriado manualmente.

#### A. Configuracao minima do Flow `Voice_Grounded_Replies_Bridge`

- Tipo: **Autolaunched Flow**.
- API Name: `Voice_Grounded_Replies_Bridge`.
- Variaveis obrigatorias:
  - `transcript` (Text, Input=true)
  - `promptResponse` (Text, Output=true)
- Acao obrigatoria:
  - Tipo: Prompt Template (`generatePromptResponse`)
  - Prompt: `Grounded_Service_Reply_Voice_Monitor`
  - Input mapeado: `Input:Transcript` <- `{!transcript}`
  - Output mapeado: `{!promptResponse}` <- `promptResponse`
- Estado final: **Active**.

#### B. Configuracao minima do Prompt `Grounded_Service_Reply_Voice_Monitor`

- API Name: `Grounded_Service_Reply_Voice_Monitor`.
- Input obrigatorio:
  - API: `Transcript`
  - Reference: `Input:Transcript`
  - Required: `true`
- O template deve retornar JSON no contrato esperado pelo componente.
- O template precisa ter:
  - ao menos 1 versao **Published**
  - versao ativa definida (`activeVersionIdentifier`)

#### C. Checklist de compatibilidade (antes de liberar)

- [ ] O Flow chama exatamente o Prompt esperado.
- [ ] O Prompt recebe `Input:Transcript` e retorna texto JSON.
- [ ] O JSON contem `responses[]`, cada item com `response` e `source`.
- [ ] O Flow esta `Active`.
- [ ] O Prompt esta `Published` e com versao ativa.
- [ ] O LWC na pagina de `VoiceCall` aponta para os nomes corretos de Flow.

#### D. Comandos uteis de verificacao

```bash
# Ver status dos FlowDefinitions
sf data query \
  --target-org <alias> \
  --query "SELECT DeveloperName, Status FROM FlowDefinition WHERE DeveloperName IN ('Get_Voice_Call_Transcript','Voice_Grounded_Replies_Bridge')"

# Reaplicar apenas metadados complementares (Flow + Prompt)
sf project deploy start \
  --target-org <alias> \
  --manifest manifest/post-install-package.xml \
  --ignore-conflicts
```

#### E. Erros comuns apos ajuste

- **Flow ativo, mas sem retorno**: variavel `promptResponse` nao marcada como output.
- **Erro de acao no Flow**: Prompt nao publicado/ativo ou nome API divergente.
- **UI sem recomendacoes**: JSON retornado pelo Prompt nao bate com o parser esperado.
- **Funciona em uma org e falha em outra**: retriever/data provider do Prompt nao existe ou nao esta acessivel na org destino.

## Observacoes importantes

- Recursos de AI/Prompt Builder podem depender de licenciamento e features da org destino.
- Se a org destino usar provider de voz diferente, mantenha polling habilitado (`Transcript Poll Interval (ms)`).
- Em upgrades, gere nova package version e reinstale upgrade usando novo `04t...`.
