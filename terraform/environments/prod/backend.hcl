# Created by terraform/global/bootstrap in the prod account.
bucket       = "rems-tfstate-333333333333-ap-south-1" # PLACEHOLDER account ID
key          = "rems/prod/primary/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
