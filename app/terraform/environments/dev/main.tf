module "vpc" {
  source = "../../modules/vpc"
  vpc_config = var.vpc_config
  common_tags = var.common_tags
  public_subnet_config = var.public_subnet_config
  private_subnet_config = var.private_subnet_config
  environment = var.environment
}

module "security_groups" {
  source = "../../modules/security_groups"
  vpc_id = module.vpc.vpc_id
  common_tags = var.common_tags
  environment = var.environment
}
