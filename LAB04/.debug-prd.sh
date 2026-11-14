# set subscription
export ARM_SUBSCRIPTION_ID="a28d37e5-0b11-4b3a-9143-cd8b6e66d5ec"

# set application / environment
export TF_VAR_application_name="devops"
export TF_VAR_environment_name="prd"

# set backend
export BACKEND_RESOURCE_GROUP="rg-terraform-state-prd"
export BACKEND_STORAGE_ACCOUNT="st4lg85il63i"
export BACKEND_CONTAINER_NAME="tfstate"
export BACKEND_KEY=$TF_VAR_application_name-$TF_VAR_environment_name

# run terraform
terraform init \
    -backend-config="resource_group_name=${BACKEND_RESOURCE_GROUP}" \
    -backend-config="storage_account_name=${BACKEND_STORAGE_ACCOUNT}" \
    -backend-config="container_name=${BACKEND_CONTAINER_NAME}" \
    -backend-config="key=${BACKEND_KEY}" 

terraform $*

rm -rf .terraform