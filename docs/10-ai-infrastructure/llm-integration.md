# LLM Integration (gateway)

**Status:** ✅ `ai-infrastructure/llm-gateway/values.yaml`, `ai-infrastructure/llm-gateway/k8s/` (ExternalSecrets, NetworkPolicy, kustomize component used by every overlay), Bedrock guardrail and gateway IAM policy (`modules/ai-platform`). 🟡 Image tag `PLACEHOLDER-pinned-version`, guardrail ID/version, proxy endpoint and region are placeholders. The values say to verify key names against the pinned chart version. ⚠️ Not deployed.

## Model groups (real values)

| Group | Primary (Bedrock) | Limits | Fallback |
|---|---|---|---|
| `rems-reasoning` | `bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0` | rpm 200, tpm 400 000 | `rems-reasoning-fallback` → `anthropic/claude-3-5-sonnet-20241022` |
| `rems-fast` | `bedrock/anthropic.claude-3-haiku-20240307-v1:0` | rpm 1000 | `rems-fast-fallback` → `openai/gpt-4o-mini` |
| `rems-embed` | `bedrock/amazon.titan-embed-text-v2:0` | – | none (vectors never leave AWS) |

Router: `routing_strategy: usage-based-routing-v2`, `num_retries: 2`, `allowed_fails: 5`, `cooldown_time: 60`.

> Model IDs are pinned to what was current when the values were written. Check model availability in ap-south-1 (`aws bedrock list-foundation-models --region ap-south-1`) and update before deploying.

## Steps

1. Terraform outputs → values:

   ```bash
   terraform -chdir=terraform/environments/prod output -json ai      # guardrail_id, guardrail_version, provider_secret_names
   terraform -chdir=terraform/environments/prod output -json aurora | jq -r .core_proxy_endpoint
   ```

   Set `guardrailIdentifier`, `guardrailVersion`, the database `endpoint` and `AWS_REGION` in `ai-infrastructure/llm-gateway/values.yaml`. Pin `image.tag` to a reviewed LiteLLM release and mirror it into ECR.

2. Enable Bedrock model access in the prod account (console: Bedrock → Model access) for the three models.
3. Put the provider keys and master key in Secrets Manager ([secrets management](../07-security/secrets-management.md)).
4. Commit. ArgoCD deploys the gateway at wave 0. The overlay patches the ExternalSecret keys per environment.
5. Create a team (tenant) budget through the admin API (from the values file comments):

   ```bash
   kubectl -n rems-ai port-forward svc/llm-gateway 4000:4000 &
   read -rs LITELLM_MASTER_KEY
   curl -s -X POST http://localhost:4000/team/new -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
     -H 'Content-Type: application/json' \
     -d '{"team_alias":"<tenant_id>","max_budget":500,"budget_duration":"30d","rpm_limit":300,"tpm_limit":300000,"models":["rems-reasoning","rems-fast","rems-embed"]}'
   unset LITELLM_MASTER_KEY
   ```

   The budget numbers are the example from the values file. Set them per tenant contract.

## Verification

```bash
kubectl -n rems-ai get pods -l app.kubernetes.io/name=llm-gateway
kubectl -n rems-ai get externalsecrets
aws bedrock get-guardrail --guardrail-identifier <guardrail-id> --guardrail-version <version> --query '{name:name,status:status}'
```

The AI gateway dashboard (`rems-ai-gateway`) shows requests, errors by provider and spend.

## Security considerations

* External fallback traffic leaves through NAT. 📋 The Network Firewall FQDN allow-list mentioned in the values comment isn't implemented. Until it is, egress is restricted only by the gateway NetworkPolicy (public 443).
* Tenant opt-out of external providers must be enforced through team model lists (exclude the `*-fallback` groups).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AccessDeniedException` from Bedrock | Model access not enabled, or the model ID isn't in the gateway IAM policy (`allowed_model_ids`) |
| `ThrottlingException` | Bedrock quota. Request an increase, or let the router fall back |
| All providers down (`RemsLLMAllProvidersDown`) | `runbooks/ai-provider-outage.md` |

## Rollback

Revert values. Model ID changes are config-only. Keep the previous model group until the new one is proven.
