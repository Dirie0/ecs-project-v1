module "vpc" {
  source = "../../modules/vpc"
  vpc_config = var.vpc_config
  common_tags = var.common_tags
}