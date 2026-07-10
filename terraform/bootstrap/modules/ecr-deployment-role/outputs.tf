output "ecr-deployment-role" {
    value = aws_iam_role.ecr_push.arn
}