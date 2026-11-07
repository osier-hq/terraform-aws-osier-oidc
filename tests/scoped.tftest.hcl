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

run "single_role" {
  command = plan

  variables {
    split_apply_role = false
    policy_arns      = ["arn:aws:iam::aws:policy/PowerUserAccess"]
  }

  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringLike["osier.dev:sub"] == "org:acme:project:platform:*"
    error_message = "single role trusts the whole project"
  }
  assert {
    condition     = length(aws_iam_role.apply) == 0
    error_message = "no apply role when not split"
  }
  assert {
    condition     = output.apply_role_arn == null
    error_message = "apply_role_arn is null when not split"
  }
  assert {
    condition     = keys(aws_iam_role_policy_attachment.plan) == ["arn:aws:iam::aws:policy/PowerUserAccess"]
    error_message = "single role carries policy_arns; plan_policy_arns is ignored"
  }
}

run "stacks_single" {
  command = plan

  variables {
    stacks           = ["prod"]
    split_apply_role = false
  }

  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringLike["osier.dev:sub"] == "org:acme:project:platform:stack:prod:*"
    error_message = "one stack renders a single string pattern"
  }
}

run "stacks_and_split" {
  command = plan

  variables {
    stacks      = ["dev", "prod"]
    policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringLike["osier.dev:sub"] == ["org:acme:project:platform:stack:dev:phase:plan", "org:acme:project:platform:stack:prod:phase:plan"]
    error_message = "plan role lists each stack's plan subject"
  }
  assert {
    condition     = jsondecode(aws_iam_role.apply[0].assume_role_policy).Statement[0].Condition.StringLike["osier.dev:sub"] == ["org:acme:project:platform:stack:dev:phase:apply", "org:acme:project:platform:stack:prod:phase:apply"]
    error_message = "apply role lists each stack's apply subject"
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.plan) == 1
    error_message = "plan role keeps ReadOnlyAccess"
  }
  assert {
    condition     = keys(aws_iam_role_policy_attachment.apply) == ["arn:aws:iam::aws:policy/AdministratorAccess"]
    error_message = "apply role carries policy_arns"
  }
}
