terraform {

  backend "s3" {

    bucket = "gatus-bootstrap-state"

    key = "bootstrap/terraform.tfstate"

    region = "us-east-1"

    encrypt = true

  }

}