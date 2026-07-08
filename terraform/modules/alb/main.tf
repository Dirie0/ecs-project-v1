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
    target_type = "ip"
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



resource "aws_lb_listener" "alb_listener" {
    load_balancer_arn = aws_lb.alb.arn
    port = 80
    protocol = "HTTP"
    default_action {
        type = "redirect"
        redirect {
            port = 443
            protocol = "HTTPS"
            status_code = "HTTP_301"
        }
    }
}


resource "aws_lb_listener" "alb_https_listener" {
    load_balancer_arn = aws_lb.alb.arn
    port = 443
    protocol = "HTTPS"
    ssl_policy = "ELBSecurityPolicy-2016-08"
    certificate_arn = var.acm_certificate_arn
    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.alb_target_group.arn
    }
}

