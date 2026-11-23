# Normal operation: DR state lives in the primary-region state bucket.
# The bootstrap stack replicates that bucket to the DR region (CRR), so during a
# primary-region outage use backend-dr-region.hcl instead (terraform init -reconfigure).
bucket       = "rems-tfstate-333333333333-ap-south-1" # PLACEHOLDER account ID
key          = "rems/prod/dr/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
