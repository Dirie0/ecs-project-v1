bucket_name  = "gatus-terraform-state-staging"
aws_region   = "us-east-1"

tags = {
  Environment = "staging"
  Project     = "gatus"
  ManagedBy   = "terraform-bootstrap"
}