# Created by terraform/global/bootstrap in the staging account.
bucket       = "rems-tfstate-222222222222-ap-south-1" # PLACEHOLDER account ID
key          = "rems/staging/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
