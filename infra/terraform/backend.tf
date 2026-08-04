# Remote state. Terraform can't create the bucket it then uses for its own
# state, so this is a two-step bootstrap:
#
#   1. Create the bucket + DynamoDB lock table once, by hand or via a tiny
#      separate "bootstrap" Terraform config:
#        aws s3api create-bucket --bucket opsboard-tfstate-<your-suffix> \
#          --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1
#        aws s3api put-bucket-versioning --bucket opsboard-tfstate-<your-suffix> \
#          --versioning-configuration Status=Enabled
#        aws dynamodb create-table --table-name opsboard-tf-locks \
#          --attribute-definitions AttributeName=LockID,AttributeType=S \
#          --key-schema AttributeName=LockID,KeyType=HASH \
#          --billing-mode PAY_PER_REQUEST
#
#   2. Fill in the bucket name below and uncomment, then run:
#        terraform init -migrate-state
#
# Until then, Terraform uses local state (fine for a first `apply`, not fine
# for a team / CI pipeline).

# terraform {
#   backend "s3" {
#     bucket         = "opsboard-tfstate-<your-suffix>"
#     key            = "opsboard/terraform.tfstate"
#     region         = "ap-south-1"
#     dynamodb_table = "opsboard-tf-locks"
#     encrypt        = true
#   }
# }
