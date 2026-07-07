resource "aws_security_group" "alb_sg" {
    name = "${var.environment}-alb-sg"
    description = "Security group for ALB"
    vpc_id = var.vpc_id

    ingress {
     from_port  = 80
     to_port    = 80
     protocol   = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
     from_port  = 443
     to_port    = 443
     protocol   = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
     from_port  = 0
     to_port    = 0
     protocol   = "-1"
     cidr_blocks = ["0.0.0.0/0"]
}
 tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-alb-sg"
    }
  )
}



resource "aws_security_group" "ecs_sg" {
  name        = "ecs_security_group"
  description = "allows port 8080 access from alb security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

