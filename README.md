# infrastructure

## Instructions

### dev

#### plan

terraform plan -var-file="devrole.tfvars"

#### apply

terraform apply -var-file="devrole.tfvars"

#### destroy

terraform destroy -var-file="devrole.tfvars"

### prod

#### plan

terraform plan -var-file="prodrole.tfvars"

#### apply

terraform apply -var-file="prodrole.tfvars"

#### destroy

terraform destroy -var-file="prodrole.tfvars"