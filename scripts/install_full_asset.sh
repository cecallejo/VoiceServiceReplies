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

echo "==> Fazendo deploy dos metadados complementares (Flows + Prompt)"
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
echo "  1) Confirmar Prompt Template Grounded_Service_Reply_Voice_Monitor com versao ativa/publicada."
echo "  2) Adicionar o componente Grounded Replies Voice Monitor na Lightning Record Page de VoiceCall."
