resource "aws_ecr_repository" "repo" {
  name = var.project_name

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "IMMMUTABLE"
}


resource "aws_ecr_lifecycle_policy" "repo_lifecycle" {
  repository = aws_ecr_repository.repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}