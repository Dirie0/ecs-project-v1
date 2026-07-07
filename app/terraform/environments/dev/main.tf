terraform {
  backend "s3" {
    bucket = var.bucket_name
    key    = "${var.environment}/terraform.tfstate"
    region = var.aws_region
    encrypt= true
    use_lockfile= true

  }
}