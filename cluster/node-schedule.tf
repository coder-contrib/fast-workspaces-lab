# Optional EKS managed node group example. Set asg_name to its backing ASG.
# This file is not applied with kubectl. Terraform manages these schedules.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "asg_name" {
  type        = string
  description = "Name of the Auto Scaling group behind the workspace node group."
}

variable "enable_evening_scale_down" {
  type        = bool
  default     = false
  description = "Set true only after workspaces and prebuilds stop using the node."
}

resource "aws_autoscaling_schedule" "warm" {
  autoscaling_group_name = var.asg_name
  scheduled_action_name  = "warm-workdays"
  recurrence             = "0 9 * * 1-5"
  time_zone              = "America/New_York"
  min_size               = 1
  desired_capacity       = 1
}

resource "aws_autoscaling_schedule" "cool" {
  count                  = var.enable_evening_scale_down ? 1 : 0
  autoscaling_group_name = var.asg_name
  scheduled_action_name  = "cool-after-work"
  recurrence             = "0 17 * * 1-5"
  time_zone              = "America/New_York"
  min_size               = 0
  desired_capacity       = 0
}
