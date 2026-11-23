bucket       = "rems-tfstate-111111111111-ap-south-1" # PLACEHOLDER
key          = "rems/dev/argocd/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
