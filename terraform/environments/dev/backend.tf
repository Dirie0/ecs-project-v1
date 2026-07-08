terraform {
  backend "s3" {
    bucket       = "gatus-terraform-state-dev"
    key          = "gatus/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true

  }
}
