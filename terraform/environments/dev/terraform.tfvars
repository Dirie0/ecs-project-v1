aws_region   = "us-east-1"
environment  = "dev"
project_name = "gatus"
domain_name  = "dirieisseprojects.co.uk"

common_tags = {
  Environment = "dev"
  Project     = "gatus"
  ManagedBy   = "terraform"
}

vpc_config = {
  cidr_block = "10.0.0.0/22"
  name       = "dev-vpc"
}

public_subnet_config = {
  public_a = {
    cidr_block = "10.0.0.0/24"
    az         = "us-east-1a"
  }

  public_b = {
    cidr_block = "10.0.1.0/24"
    az         = "us-east-1b"
  }
}

private_subnet_config = {
  private_a = {
    cidr_block = "10.0.2.0/24"
    az         = "us-east-1a"
    nat_key    = "public_a"
  }

  private_b = {
    cidr_block = "10.0.3.0/24"
    az         = "us-east-1b"
    nat_key    = "public_b"
  }
}

task_cpu = 256

task_memory = 512

app_port = 8080

app_count = 1

ecr_repository_url = "930067561901.dkr.ecr.us-east-1.amazonaws.com/gatus"