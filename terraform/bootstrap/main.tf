
module "oidc" {
  source = "./modules/oidc"
}



module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
}


module "state_buckets" {
  for_each    = toset(var.environments)
  source      = "./modules/s3"
  bucket_name = "${var.project_name}-terraform-state-${each.key}"
  region      = var.aws_region
  tags = merge(
    var.tags,
    {
      Environment = each.key
    }
  )

}


module "deployment_roles" {
  for_each          = toset(var.environments)
  source            = "./modules/deployment-role"
  github_repo       = var.github_repo
  oidc_provider_arn = module.oidc.github_oidc_provider_arn
  environment       = each.key
  project_name      = var.project_name

}




module "ecr_deployment_role" {

  source                   = "./modules/ecr-deployment-role"
  github_repo              = var.github_repo
  github_oidc_provider_arn = module.oidc.github_oidc_provider_arn
  project_name             = var.project_name
  ecr_repository_arn       = module.ecr.repository_arn

}