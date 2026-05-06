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

## 6) Pos-instalacao

Na org destino:

- Verifique se os flows estao ativos:
  - `Get_Voice_Call_Transcript`
  - `Voice_Grounded_Replies_Bridge`
- Verifique se o Prompt Template `Grounded_Service_Reply_Voice_Monitor` esta publicado e ativo.
- Adicione `Grounded Replies Voice Monitor` na Lightning Record Page de `VoiceCall`.
- Ajuste propriedades do componente conforme necessidade.

## Observacoes importantes

- Recursos de AI/Prompt Builder podem depender de licenciamento e features da org destino.
- Se a org destino usar provider de voz diferente, mantenha polling habilitado (`Transcript Poll Interval (ms)`).
- Em upgrades, gere nova package version e reinstale upgrade usando novo `04t...`.
