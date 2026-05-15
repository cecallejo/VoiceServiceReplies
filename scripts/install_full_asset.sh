#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   ./scripts/install_full_asset.sh <alias-org-destino>
#
# Exemplo:
#   ./scripts/install_full_asset.sh prod

if [[ $# -lt 1 ]]; then
  echo "Uso: $0 <alias-org-destino>"
  exit 1
fi

TARGET_ORG="$1"
PACKAGE_VERSION_ID="04tHp000001Rd16IAC"
POST_INSTALL_MANIFEST="manifest/post-install-package.xml"

echo "==> Instalando pacote promovido na org: ${TARGET_ORG}"
sf package install \
  --package "${PACKAGE_VERSION_ID}" \
  --target-org "${TARGET_ORG}" \
  --wait 30 \
  --publish-wait 10 \
  --no-prompt

echo "==> Fazendo deploy dos metadados complementares (Flows + Prompts)"
sf project deploy start \
  --target-org "${TARGET_ORG}" \
  --manifest "${POST_INSTALL_MANIFEST}" \
  --ignore-conflicts

echo "==> Validando se os flows foram implantados"
sf data query \
  --target-org "${TARGET_ORG}" \
  --query "SELECT DeveloperName, Status FROM FlowDefinition WHERE DeveloperName IN ('Get_Voice_Call_Transcript','Voice_Grounded_Replies_Bridge')"

echo "==> Processo concluido."
echo "Checklist manual:"
echo "  1) Confirmar Prompt Templates Grounded_Service_Reply_Voice_Monitor, OnCall_Sentiment_Analysis e Post_Call_Voice_Sentiment_Analysis com versao ativa/publicada."
echo "  2) Confirmar objeto de log Voice_Service_Reply__c e campos (Voice_Call__c, Search_Query__c, Answer_1__c, Answer_2__c)."
echo "  3) Adicionar o componente Grounded Replies Voice Monitor na Lightning Record Page de VoiceCall."
