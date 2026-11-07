output "role_arn" {
  description = "ARN of the plan role, or of the single role when split_apply_role is false."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "ARN of the apply role. Null unless split_apply_role is true."
  value       = var.split_apply_role ? aws_iam_role.apply[0].arn : null
}

output "provider_arn" {
  description = "ARN of the IAM OIDC identity provider the roles trust."
  value       = local.provider_arn
}
