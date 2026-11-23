bucket       = "rems-tfstate-444444444444-ap-south-1" # PLACEHOLDER (shared-services account)
key          = "rems/cicd/github/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
