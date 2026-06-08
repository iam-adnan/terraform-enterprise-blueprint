output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_names" {
  description = "Map of task definition key to ECS service name."
  value       = { for k, svc in aws_ecs_service.this : k => svc.name }
}

output "service_arns" {
  description = "Map of task definition key to ECS service ARN."
  value       = { for k, svc in aws_ecs_service.this : k => svc.id }
}

output "task_definition_arns" {
  description = "Map of task definition key to latest task definition ARN."
  value       = { for k, td in aws_ecs_task_definition.this : k => td.arn }
}

output "execution_role_arn" {
  description = "ARN of the shared ECS execution IAM role."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the shared ECS task IAM role."
  value       = aws_iam_role.task.arn
}

output "security_group_id" {
  description = "ID of the ECS tasks security group."
  value       = aws_security_group.ecs.id
}

output "log_group_names" {
  description = "Map of task definition key to CloudWatch log group name."
  value       = { for k, lg in aws_cloudwatch_log_group.this : k => lg.name }
}
