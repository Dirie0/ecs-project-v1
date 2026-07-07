output "security_group_alb_id" {
  value = aws_security_group.alb_sg.id
}

output "security_group_ecs_id" {
  value = aws_security_group.ecs_sg.id
}