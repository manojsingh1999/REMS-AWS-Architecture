# Created by terraform/global/bootstrap in the dev account.
bucket       = "rems-tfstate-111111111111-ap-south-1" # PLACEHOLDER account ID
key          = "rems/dev/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
