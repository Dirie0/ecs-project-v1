# bootstrap/modules/deploy-role/main.tf

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.project_name}-${var.environment}-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid = "AppServices"
    actions = [
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "acm:*",
      "ec2:*",
      "logs:*",
      "route53:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "PassRoleScoped"
    actions = [
      "iam:GetRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::*:role/${var.environment}-ecs-task-execution-role",
      "arn:aws:iam::*:role/${var.environment}-ecs-task-role",
    ]
  }

  statement {
    sid     = "StateBackend"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::gatus-terraform-state-${var.environment}",
      "arn:aws:s3:::gatus-terraform-state-${var.environment}/*",
    ]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.project_name}-${var.environment}-deploy-policy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.permissions.json
}