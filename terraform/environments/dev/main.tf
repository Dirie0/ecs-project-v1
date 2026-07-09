module "vpc" {
  source                = "../../modules/vpc"
  vpc_config            = var.vpc_config
  common_tags           = var.common_tags
  public_subnet_config  = var.public_subnet_config
  private_subnet_config = var.private_subnet_config
  environment           = var.environment
}

module "security_groups" {
  source      = "../../modules/security_groups"
  vpc_id      = module.vpc.vpc_id
  common_tags = var.common_tags
  environment = var.environment
}

module "iam" {
  source      = "../../modules/iam"
  common_tags = var.common_tags
  environment = var.environment
}

module "ecr" {
  source       = "../../modules/ecr"
  project_name = var.project_name
  environment  = var.environment
}

module "route_53" {
  source      = "../../modules/route_53"
  domain_name = var.domain_name
  common_tags = var.common_tags
}

module "acm" {
  source      = "../../modules/acm"
  zone_id     = module.route_53.zone_id
  domain_name = var.domain_name
  depends_on = [
    module.route_53
  ]
}

module "alb" {
  source                = "../../modules/alb"
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.security_group_alb_id
  common_tags           = var.common_tags
  environment           = var.environment
  acm_certificate_arn   = module.acm.certificate_arn
  depends_on = [
    module.acm
  ]
}

module "cloudwatch" {
  source       = "../../modules/cloudwatch"
  project_name = var.project_name
  environment  = var.environment
  common_tags  = var.common_tags
}

module "ecs" {
  source                 = "../../modules/ecs"
  project_name           = var.project_name
  ecs_execution_role_arn = module.iam.ecs_task_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn
  task_cpu               = var.task_cpu
  task_memory            = var.task_memory
  app_port               = var.app_port
  ecr_repository_url     = module.ecr.repository_url
  log_group              = module.cloudwatch.app_log_group
  common_tags            = var.common_tags
  environment            = var.environment
  aws_region             = var.aws_region
  app_image              = var.app_image
  private_subnet_ids     = module.vpc.private_subnet_ids
  ecs_security_group_id  = module.security_groups.security_group_ecs_id
  target_group_arn       = module.alb.target_group_arn
  app_count              = var.app_count
  depends_on = [
    module.alb
  ]
}

module "route_53_record" {
  source           = "../../modules/route_53_record"
  zone_id          = module.route_53.zone_id
  domain_name      = var.domain_name
  aws_alb_dns_name = module.alb.alb_dns_name
  aws_alb_zone_id  = module.alb.alb_zone_id
  depends_on = [
    module.ecs
  ]
}