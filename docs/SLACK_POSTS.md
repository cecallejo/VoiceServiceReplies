## Post para Slack (PT-BR)

🚀 **Novo asset: Voice Service Replies (LWC + Apex + Flow + Prompt)**

Pessoal, disponibilizei o **Voice Service Replies**, um componente reutilizavel para `VoiceCall` que gera **recomendacoes de resposta em tempo real** com grounding em Knowledge.

**O que o componente faz**
- Monitora a transcricao da chamada (evento + fallback por polling)
- Agrupa por volume de palavras
- Aciona Flow + Prompt para gerar respostas sugeridas
- Exibe recomendacoes com referencia de fonte no card do VoiceCall

**Documentacao**
- Guia geral + configuracao detalhada de Flow/Prompt: `README.md`
- Guia de empacotamento/instalacao: `docs/PACKAGING.md`
- Repositorio: [https://github.com/cecallejo/VoiceServiceReplies](https://github.com/cecallejo/VoiceServiceReplies)

**Instalacao em ORG**
- Pacote base (LWC + Apex)
  - Prod/DE: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd16IAC`
  - Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd16IAC`
- Instalacao completa (pacote + Flows + Prompt):
  - `./scripts/install_full_asset.sh <alias-org-destino>`

Se quiserem, posso ajudar no primeiro setup em sandbox para validar ponta a ponta.

---

## Slack Post (EN)

🚀 **New asset: Voice Service Replies (LWC + Apex + Flow + Prompt)**

Team, I have published **Voice Service Replies**, a reusable `VoiceCall` component that delivers **real-time response recommendations** grounded on Knowledge.

**What the component does**
- Monitors call transcript (event-driven + polling fallback)
- Batches transcript by word threshold
- Triggers Flow + Prompt to generate suggested replies
- Shows recommendations with source references in the VoiceCall card

**Documentation**
- General guide + detailed Flow/Prompt setup: `README.md`
- Packaging/install guide: `docs/PACKAGING.md`
- Repository: [https://github.com/cecallejo/VoiceServiceReplies](https://github.com/cecallejo/VoiceServiceReplies)

**Org installation**
- Base package (LWC + Apex)
  - Prod/DE: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd16IAC`
  - Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tHp000001Rd16IAC`
- Full installation (package + Flows + Prompt):
  - `./scripts/install_full_asset.sh <target-org-alias>`

If useful, I can help with a first sandbox setup and end-to-end validation.
