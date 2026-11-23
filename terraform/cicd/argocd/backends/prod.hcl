bucket       = "rems-tfstate-333333333333-ap-south-1" # PLACEHOLDER
key          = "rems/prod/argocd/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
