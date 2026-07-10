resource "aws_s3_bucket" "bootstrap_state" {

  bucket = "${var.project_name}-bootstrap-state"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform-bootstrap-state"
  }
}


resource "aws_s3_bucket_versioning" "bootstrap_state" {

  bucket = aws_s3_bucket.bootstrap_state.id

  versioning_configuration {
    status = "Enabled"
  }

}


resource "aws_s3_bucket_server_side_encryption_configuration" "bootstrap_state" {

  bucket = aws_s3_bucket.bootstrap_state.id

  rule {

    apply_server_side_encryption_by_default {

      sse_algorithm = "AES256"

    }

  }

}


resource "aws_s3_bucket_public_access_block" "bootstrap_state" {

  bucket = aws_s3_bucket.bootstrap_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

}