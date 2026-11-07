data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "osier" {
  count = var.create_provider ? 1 : 0

  url            = "https://${var.issuer}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS has validated the issuer's certificate chain itself since 2023 and
  # ignores this value, but the argument is still required.
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]
}

locals {
  role_name = coalesce(var.role_name, "osier-${var.project}")
  base      = "org:${var.org}:project:${var.project}"

  provider_arn = var.create_provider ? aws_iam_openid_connect_provider.osier[0].arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.issuer}"

  # Same subject patterns as the Osier Worker (awsSubjectPattern).
  plan_patterns = (
    var.split_apply_role
    ? (length(var.stacks) == 0 ? ["${local.base}:stack:*:phase:plan"] : [for s in var.stacks : "${local.base}:stack:${s}:phase:plan"])
    : (length(var.stacks) == 0 ? ["${local.base}:*"] : [for s in var.stacks : "${local.base}:stack:${s}:*"])
  )
  apply_patterns = length(var.stacks) == 0 ? ["${local.base}:stack:*:phase:apply"] : [for s in var.stacks : "${local.base}:stack:${s}:phase:apply"]

  # StringLike takes a string for one pattern and a list otherwise. The two
  # branches have different types, so they go through JSON to unify.
  trust = {
    for name, patterns in { plan = local.plan_patterns, apply = local.apply_patterns } : name => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = local.provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = { "${var.issuer}:aud" = "sts.amazonaws.com" }
          StringLike = {
            "${var.issuer}:sub" = jsondecode(length(patterns) == 1 ? jsonencode(patterns[0]) : jsonencode(patterns))
          }
        }
      }]
    })
  }
}

resource "aws_iam_role" "plan" {
  name               = local.role_name
  assume_role_policy = local.trust["plan"]
}

resource "aws_iam_role" "apply" {
  count = var.split_apply_role ? 1 : 0

  name               = "${local.role_name}-apply"
  assume_role_policy = local.trust["apply"]
}

resource "aws_iam_role_policy_attachment" "plan" {
  for_each = toset(var.split_apply_role ? var.plan_policy_arns : var.policy_arns)

  role       = aws_iam_role.plan.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each = toset(var.split_apply_role ? var.policy_arns : [])

  role       = aws_iam_role.apply[0].name
  policy_arn = each.value
}
