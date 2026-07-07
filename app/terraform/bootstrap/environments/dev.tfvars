bucket_name  = "gatus-terraform-state-dev"
aws_region   = "us-east-1"

tags = {
  Environment = "dev"
  Project     = "gatus"
  ManagedBy   = "terraform-bootstrap"
}