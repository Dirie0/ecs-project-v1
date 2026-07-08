module "s3" {
    source = "./modules/s3"
    region = var.aws_region
    bucket_name = var.bucket_name
    tags = var.tags
    
}


# module "oidc" {
#     source = "./modules/oidc"
# }

module "deploy_role" {
    source = "./modules/deployment-role"
    github_repo = var.github_repo
    oidc_provider_arn = var.github_oidc_provider_arn
    environment = var.environment
    project_name = var.project_name

}