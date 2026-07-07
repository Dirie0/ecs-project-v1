bucket_name  = "gatus-terraform-state-prod"
aws_region   = "us-east-1"

tags = {
  Environment = "prod"
  Project     = "gatus"
  ManagedBy   = "terraform-bootstrap"
}