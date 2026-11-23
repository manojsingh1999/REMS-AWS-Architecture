# AWS Cost Estimation

**Status:** ✅ Reproducible model `scripts/cost_model.py`, narrative in `documentation/06-cost-model.md`. ⚠️ **Estimates only.** The script uses approximate ap-south-1 on-demand list prices hard-coded in the file. Re-check them with the AWS Pricing Calculator before any budget decision. No AWS bill exists, because nothing is deployed.

## Run the model

```bash
python3 scripts/cost_model.py
```

Output (current repository version, USD per month):

| Environment | On-demand | Optimized | Saving |
|---|---:|---:|---:|
| prod | 15,093 | 11,653 | 23 % |
| prod-dr | 4,726 | 3,614 | 24 % |
| staging | 4,363 | 3,442 | 21 % |
| dev | 1,872 | 1,357 | 28 % |
| shared + security | 523 | 523 | 0 % |
| **All environments** | **26,576** | **20,588** | **23 %** |

Prod infrastructure excluding AI: 11,257 USD. Bedrock: 3,836 USD (25 % of prod). That works out to about 113 USD of infrastructure + 38 USD of AI per tenant at 100 tenants.

## Assumptions behind the numbers

* Region ap-south-1 (DR ap-southeast-1), 730 hours/month.
* Capacity from `documentation/05-capacity-plan.md` (50 M events/day, 20 → 100 tenants, 5× peaks).
* Bedrock usage from the AI capacity model (`ai-infrastructure/README.md`): ~48 M reasoning tokens/day, tiered Sonnet/Haiku, 20 % cache hits.
* Data transfer: 1.5 TB out, 0.8 TB cross-region per month (prod).

## Updating prices

Edit the `P` dictionary at the top of `scripts/cost_model.py` (section "unit prices (approximate, ap-south-1)"), then re-run. Pull current prices with:

```bash
aws pricing get-products --region us-east-1 --service-code AmazonEC2 \
  --filters Type=TERM_MATCH,Field=instanceType,Value=m7g.large Type=TERM_MATCH,Field=regionCode,Value=ap-south-1 \
            Type=TERM_MATCH,Field=operatingSystem,Value=Linux Type=TERM_MATCH,Field=tenancy,Value=Shared \
            Type=TERM_MATCH,Field=preInstalledSw,Value=NA Type=TERM_MATCH,Field=capacitystatus,Value=Used \
  --query 'PriceList[0]' --output text | jq '.terms.OnDemand[].priceDimensions[].pricePerUnit.USD'
```

## Guardrails in place

* AWS Budgets per environment (`monthly_budget_usd`, prod placeholder 30 000) with alerts.
* Cost Anomaly Detection (one monitor per account, created by the primary stack).
* Per-tenant LLM budgets in the gateway.
