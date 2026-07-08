bucket_name  = "gatus-terraform-state-staging"
aws_region   = "us-east-1"

tags = {
  Environment = "staging"
  Project     = "gatus"
  ManagedBy   = "terraform-bootstrap"
}

github_oidc_provider_arn = "arn:aws:iam::930067561901:oidc-provider/token.actions.githubusercontent.com"
github_repo       = "Dirie0/ecs-project-v1"
environment        = "staging"
project_name        = "gatus"