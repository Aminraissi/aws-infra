# The us-east-1 provider alias must be passed in from the root module.
# Child modules can't declare providers themselves, so we just
# declare the required_providers alias here for clarity.
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.50"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
