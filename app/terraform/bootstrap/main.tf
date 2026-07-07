module "s3" {
    source = "./modules/s3"
    region = var.aws_region
    bucket_name = var.bucket_name
    tags = var.tags
    
}