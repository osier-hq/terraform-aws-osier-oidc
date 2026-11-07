mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  org     = "acme"
  project = "platform"
}

run "project_scope" {
  command = plan

  assert {
    condition     = aws_iam_role.plan.name == "osier-platform"
    error_message = "plan role is named osier-<project>"
  }
  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringLike["osier.dev:sub"] == "org:acme:project:platform:stack:*:phase:plan"
    error_message = "plan role trusts the plan-phase subject"
  }
  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["osier.dev:aud"] == "sts.amazonaws.com"
    error_message = "audience is sts.amazonaws.com"
  }
  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "action is AssumeRoleWithWebIdentity"
  }
  assert {
    condition     = aws_iam_role.apply[0].name == "osier-platform-apply"
    error_message = "apply role is named <role_name>-apply"
  }
  assert {
    condition     = jsondecode(aws_iam_role.apply[0].assume_role_policy).Statement[0].Condition.StringLike["osier.dev:sub"] == "org:acme:project:platform:stack:*:phase:apply"
    error_message = "apply role trusts the apply-phase subject"
  }
  assert {
    condition     = output.apply_role_arn != null
    error_message = "apply_role_arn is set when split"
  }
  assert {
    condition     = keys(aws_iam_role_policy_attachment.plan) == ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    error_message = "plan role gets ReadOnlyAccess by default"
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.apply) == 0
    error_message = "apply role has no policies unless policy_arns is given"
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.osier) == 1
    error_message = "provider is created by default"
  }
}

run "existing_provider" {
  command = plan

  variables {
    create_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.osier) == 0
    error_message = "no provider resource when create_provider = false"
  }
  assert {
    condition     = startswith(output.provider_arn, "arn:aws:iam::")
    error_message = "provider_arn is an IAM ARN"
  }
  assert {
    condition     = endswith(output.provider_arn, ":oidc-provider/osier.dev")
    error_message = "provider_arn points at the osier.dev provider"
  }
}
