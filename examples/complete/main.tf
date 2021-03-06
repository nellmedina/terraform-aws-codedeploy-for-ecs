variable "vpc_id" {
  default = "vpc-02e09d5fbf4b98211"
}

variable "subnets" {
  default = ["subnet-04676ca5151426d2b", "subnet-053b91915bbcffd18"]
}

module "codedeploy" {
  source                     = "../../"
  name                       = "ecs-codedeploy"
  ecs_cluster_name           = aws_ecs_cluster.example.name
  ecs_service_name           = module.ecs_fargate.ecs_service_name
  lb_listener_arns           = [module.alb.http_alb_listener_arn]
  blue_lb_target_group_name  = module.alb.alb_target_group_name
  green_lb_target_group_name = aws_lb_target_group.green.name

  auto_rollback_enabled            = true
  auto_rollback_events             = ["DEPLOYMENT_FAILURE"]
  action_on_timeout                = "STOP_DEPLOYMENT"
  wait_time_in_minutes             = 20
  termination_wait_time_in_minutes = 20
  test_traffic_route_listener_arns = []
  iam_path                         = "/service-role/"
  description                      = "This is example"

  tags = {
    Environment = "prod"
  }
}

module "ecs_fargate" {
  source                    = "git::https://github.com/nellmedina/terraform-aws-ecs-fargate.git"
  name                      = "codedeploy-for-ecs"
  container_name            = local.container_name
  container_port            = local.container_port
  cluster                   = aws_ecs_cluster.example.arn
  subnets                   = var.subnets
  target_group_arn          = module.alb.alb_target_group_arn
  vpc_id                    = var.vpc_id
  container_definitions     = data.template_file.default.rendered
  # ecs_task_execution_policy = "${data.aws_iam_policy.ecs_task_execution.policy}"

  desired_count                     = 1
  assign_public_ip                  = true
  health_check_grace_period_seconds = 60
  deployment_controller_type        = "CODE_DEPLOY"
}

data "template_file" "default" {
  template = "${file("${path.module}/container_definitions.json")}"

  vars = {
    container_name = "${local.container_name}"
    container_port = "${local.container_port}"
  }
}

locals {
  container_name = "springboot-service-1"
  container_port = "${module.alb.alb_target_group_port}"
}

resource "aws_ecs_cluster" "example" {
  name = "ecs-codedeploy-cluster"
}

data "aws_iam_policy" "ecs_task_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_lb_target_group" "green" {
  name        = "green"
  vpc_id      = var.vpc_id
  port        = "${local.container_port}"
  protocol    = "HTTP"
  target_type = "ip"
}

module "alb" {
  source                     = "git::https://github.com/nellmedina/terraform-aws-alb.git"
  name                       = "ecs-alb-codedeploy"
  vpc_id                     = var.vpc_id
  subnets                    = var.subnets
  access_logs_bucket         = module.s3_lb_log.s3_bucket_id
  enable_https_listener      = false
  enable_http_listener       = true
  enable_deletion_protection = false

  target_group_port          = 8080
}

module "s3_lb_log" {
  source                = "git::https://github.com/tmknom/terraform-aws-s3-lb-log.git?ref=tags/1.0.0"
  name                  = "s3-lb-log-codedeploy-for-ecs-${data.aws_caller_identity.current.account_id}"
  logging_target_bucket = "${module.s3_access_log.s3_bucket_id}"
  force_destroy         = true
}

module "s3_access_log" {
  source        = "git::https://github.com/tmknom/terraform-aws-s3-access-log.git?ref=tags/1.0.0"
  name          = "s3-access-log-codedeploy-for-ecs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# module "vpc" {
#   source                    = "git::https://github.com/tmknom/terraform-aws-vpc.git?ref=tags/1.0.0"
#   cidr_block                = "${local.cidr_block}"
#   name                      = "codedeploy-for-ecs"
#   public_subnet_cidr_blocks = ["${cidrsubnet(local.cidr_block, 8, 0)}", "${cidrsubnet(local.cidr_block, 8, 1)}"]
#   public_availability_zones = ["${data.aws_availability_zones.available.names}"]
# }

# locals {
#   cidr_block = "10.255.0.0/16"
# }

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}
