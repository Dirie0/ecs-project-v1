module "vpc" {
  source = "../../modules/vpc"

  vpc_config = var.vpc_config
  vpc_tag = var.vpc_tag
}