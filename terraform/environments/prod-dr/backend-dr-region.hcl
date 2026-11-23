# Break-glass backend used only when the primary region is unavailable (replica of the state bucket).
bucket       = "rems-tfstate-333333333333-ap-southeast-1" # PLACEHOLDER account ID
key          = "rems/prod/dr/terraform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
