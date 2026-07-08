resource "aws_lb" "alb" {
    name = "${var.environment}-alb"
    load_balancer_type = "application"
    internal = false
    security_groups = [var.alb_security_group_id]
    subnets = var.public_subnet_ids
    enable_deletion_protection = false
    tags = merge( var.common_tags, 
            { Name = "${var.environment}-alb"
              Service = "alb" } )


}


resource "aws_lb_target_group" "alb_target_group" {
    name = "${var.environment}-alb-tg"
    port = 8080
    protocol = "HTTP"
    vpc_id = var.vpc_id
    health_check {
        path = "/health"
        interval = 30
        timeout = 5
        healthy_threshold = 5
        unhealthy_threshold = 2
        matcher = "200-299" 
}
    tags = merge( var.common_tags, 
            { Name = "${var.environment}-alb-tg"
              Service = "alb" } )
}




