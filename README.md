# API Gateway and AWS SQS integration  using terraform

The terraform configuration creates and integrates an AWS API Gateway with a AWS Simple Queue Service. 

## Resources created:

1. AWS API Gateway
2. AWS SQS
3. AWS IAM Roles :  AWS CloudWatch and SQS access
4. AWS IAM policy 

## Installing Terraform

If you have Homebrew installed you can install terraform by typing

```bash
    $ brew install terraform
```

Otherwise, please download the latest version of terraform binary [here](https://www.terraform.io/downloads.html).

## Prerequisites

1. An AWS bucket must exist with the same name as in the main.tf file:

   ```
   backend "s3" {
      bucket         = "apigw-sqs-salesforce"
      key            = "non-prod/dev.tfstate"
      region         = "us-east-1"
      dynamodb_table = "s3-state-lock"
      encrypt        = true
   }
   ```

   The bucket can be called anything, the config must be updated to match the bucket name. The AWS account used to run the script must have permissions to add/update on the s3 bucket.




2. A DynamoDb table must exist with the same name as the dynamodb_table attribite in the config file

## Running the terraform configuration

Once the terraform binary is installed, run the below commands;

1. To check if the terraform is installed properly.

```bash
    $ terraform -version
```

The terraform code is configured to use the s3 bucket as remote backend for storing and managing the terraform state file. A DynamoDB table takes cares of the state locking mechanism, i.e., it prevents another user from triggering an infra build at the same time.

**Note** : The AWS CLI should be installed and configured with sufficient user level permissions for enabling the terraform to create aws resources.

**Note** : A separate AWS account must be used run terraform with production/non-production properties. 




2. Initialize terraform configuration.

```bash
$ terraform init
```

   
3.  Create a terraform plan.

```bash
$ terraform plan -var-file="dev.tfvars"
```




4.  Deploy the terraform configuration.

```bash
$ terraform apply --auto-approve -var-file="dev.tfvars"
```
