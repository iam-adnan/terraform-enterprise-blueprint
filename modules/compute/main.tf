# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group — one per task definition, named by key (not index)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  for_each = var.task_definitions

  name              = "/ecs/${var.cluster_name}/${each.key}"
  retention_in_days = var.environment == "prod" ? 90 : 14

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM — Execution role (ECS control plane pulling images + pushing logs)
#        Task role (application runtime permissions)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.cluster_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.cluster_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = var.tags
}

# Minimal CloudWatch Logs permissions for the task role.
data "aws_iam_policy_document" "task_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/ecs/${var.cluster_name}/*"]
  }
}

resource "aws_iam_role_policy" "task_logs" {
  name   = "ecs-task-logs"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_logs.json
}

# ---------------------------------------------------------------------------
# Security Group — dynamic ingress blocks built from the ingress_rules map.
# Map iteration prevents positional-index drift when rules are added/removed.
# ---------------------------------------------------------------------------

resource "aws_security_group" "ecs" {
  name        = "${var.cluster_name}-ecs-sg"
  description = "Security group for ECS tasks in ${var.cluster_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-ecs-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# ECS Task Definitions — for_each over the task_definitions map.
# Each task gets its own family name derived from the map key.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  for_each = var.task_definitions

  family                   = "${var.cluster_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.value.image
      essential = true

      portMappings = each.value.port > 0 ? [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ] : []

      environment = [
        for env_key, env_val in each.value.environment_vars : {
          name  = env_key
          value = env_val
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.cluster_name}/${each.key}"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      readonlyRootFilesystem = true
      user                   = "1000"
    }
  ])

  tags = merge(var.tags, { Service = each.key })

  depends_on = [aws_cloudwatch_log_group.this]
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# ECS Services — one per task definition map entry
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  for_each = var.task_definitions

  name            = each.key
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = 100
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  lifecycle {
    # Ignore desired_count so auto-scaling can manage it after initial deployment.
    ignore_changes = [desired_count]
  }

  tags       = merge(var.tags, { Service = each.key })
  depends_on = [aws_iam_role_policy_attachment.execution_managed]
}

# ---------------------------------------------------------------------------
# Application Auto Scaling — scales each service independently via its map key
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  for_each = var.task_definitions

  max_capacity       = each.value.max_capacity
  min_capacity       = each.value.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_out" {
  for_each = var.task_definitions

  name               = "${each.key}-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "scale_in" {
  for_each = var.task_definitions

  name               = "${each.key}-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# CloudWatch alarms drive the scale-out/in policies.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.task_definitions

  alarm_name          = "${var.cluster_name}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Scale out ${each.key} when CPU exceeds 75%"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_out[each.key].arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  for_each = var.task_definitions

  alarm_name          = "${var.cluster_name}-${each.key}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Scale in ${each.key} when CPU drops below 20%"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_in[each.key].arn]
  tags          = var.tags
}
