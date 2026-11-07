# terraform-aws-osier-oidc

An OpenTofu / Terraform module that lets [Osier](https://osier.dev) run `tofu plan` and `tofu apply` in your AWS account without long-lived access keys. Osier issues a short-lived OIDC token for each run; this module creates the IAM OIDC identity provider for `osier.dev` and the IAM roles whose trust policy accepts only your organisation's project.

## Prerequisites

- An AWS account and credentials that can create IAM identity providers and roles.
- OpenTofu or Terraform `>= 1.8.0` and the `hashicorp/aws` provider `>= 5.0`.
- Your Osier organisation slug and project slug.

## Usage

Apply this once in the target account, then paste the two role ARNs into Osier.

```hcl
module "osier" {
  source  = "github.com/osier-hq/terraform-aws-osier-oidc?ref=v0.1.0"
  org     = "acme"
  project = "platform"
  # stacks = ["prod"]            # only for a stack override (its Test carries that stack)
  plan_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]       # what plan runs may do
  policy_arns      = ["arn:aws:iam::aws:policy/AdministratorAccess"]  # what apply runs may do: change to least privilege
}
output "osier_role_arn"       { value = module.osier.role_arn }
output "osier_apply_role_arn" { value = module.osier.apply_role_arn }
```

The module creates:

- `aws_iam_openid_connect_provider` for `https://osier.dev` (skip with `create_provider = false`).
- A plan role (`osier-<project>`) and an apply role (`osier-<project>-apply`), each trusting only the `sub` claims of your project.
- Attachments for the managed policies you list in `plan_policy_arns` and `policy_arns`.

`AdministratorAccess` in the snippet is a starting point. Replace `policy_arns` with the least privilege your stacks need.

## Separate plan and apply

`tofu plan` executes your repository's code (providers, `data "external"` and similar) before anyone approves a change. If that code ran with apply permissions, anyone who can open a pull request could use them. By default this module therefore creates two roles:

- the plan role, trusting only `phase:plan` tokens, with `plan_policy_arns` (read-only by default);
- the apply role, trusting only `phase:apply` tokens, with `policy_arns`.

Set `split_apply_role = false` to get one role for both phases, carrying `policy_arns`. That is discouraged: plan-time code then holds apply permissions. Do it only if you accept that risk.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `org` | Osier organisation slug. | `string` | required |
| `project` | Osier project slug. | `string` | required |
| `stacks` | Narrow the roles to these stacks. Empty means every stack. | `list(string)` | `[]` |
| `split_apply_role` | Create a separate apply role. | `bool` | `true` |
| `plan_policy_arns` | Policies on the plan role when split. Ignored otherwise. | `list(string)` | `["arn:aws:iam::aws:policy/ReadOnlyAccess"]` |
| `policy_arns` | Policies on the apply role when split, otherwise on the single role. | `list(string)` | `[]` |
| `role_name` | Plan (or single) role name. The apply role is `<role_name>-apply`. | `string` | `null` (`osier-<project>`) |
| `create_provider` | Create the OIDC identity provider. | `bool` | `true` |
| `issuer` | Osier issuer host, without a scheme. | `string` | `"osier.dev"` |

`plan_policy_arns` and `policy_arns` are `for_each` keys, so their values must be known at plan time. To attach a policy created in the same configuration, attach it outside the module with `aws_iam_role_policy_attachment` on the module's role, or pass the ARNs of policies that already exist:

```hcl
resource "aws_iam_role_policy_attachment" "osier_apply_extra" {
  role       = "osier-platform-apply"   # "osier-<project>-apply", or "<role_name>-apply" when role_name is set
  policy_arn = aws_iam_policy.deploy.arn
  depends_on = [module.osier]
}
```

For the plan role use `"osier-<project>"` (or `role_name`) instead.

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | The plan role, or the single role when `split_apply_role = false`. |
| `apply_role_arn` | The apply role. `null` unless split. |
| `provider_arn` | The OIDC identity provider the roles trust. |

## Console users

If you create the provider and roles in the AWS console, create an IAM OIDC provider with URL `https://osier.dev` and audience `sts.amazonaws.com`, then create roles with these trust policies. Replace `<ACCOUNT_ID>` with your account id. Attach `ReadOnlyAccess` (or narrower read-only policies) to the plan role and least-privilege policies to the apply role.

Plan role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/osier.dev" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "osier.dev:aud": "sts.amazonaws.com" },
      "StringLike": { "osier.dev:sub": "org:acme:project:platform:stack:*:phase:plan" }
    }
  }]
}
```

Apply role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/osier.dev" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "osier.dev:aud": "sts.amazonaws.com" },
      "StringLike": { "osier.dev:sub": "org:acme:project:platform:stack:*:phase:apply" }
    }
  }]
}
```

For a single role use `org:acme:project:platform:*`.

## Second project in the same account

An account can hold only one OIDC provider per issuer URL. For the second project, set `create_provider = false`; the module then trusts the existing `osier.dev` provider by ARN.

```hcl
module "osier_second" {
  source          = "github.com/osier-hq/terraform-aws-osier-oidc?ref=v0.1.0"
  org             = "acme"
  project         = "billing"
  create_provider = false
  policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]  # what apply runs may do: change to least privilege
}
```

The plan role keeps the `ReadOnlyAccess` default. Put this in a separate configuration from the one that created the identity provider, or add `depends_on = [module.osier]` if both are in the same configuration, so the provider exists first.

## Stacks

`stacks = ["dev", "prod"]` narrows the trust to those stacks. With the default split, the plan role trusts `org:acme:project:platform:stack:dev:phase:plan` and the same for `prod`; the apply role trusts the `phase:apply` equivalents. Without `stacks`, any stack of the project is trusted (`stack:*`). With `split_apply_role = false`, the single role trusts `stack:<name>:*` per stack, or `org:<org>:project:<project>:*` without stacks.

A module narrowed with `stacks` is for a stack override, not for the project connection: the project connection's Test token carries no stack (`…:stack:-:phase:plan`), so a narrowed role answers "Not authorized" to it.

## Thumbprint

The identity provider is created with a placeholder thumbprint (`ffffffffffffffffffffffffffffffffffffffff`). Since 2023 AWS validates the issuer's certificate chain against its own trusted CAs and ignores the thumbprint, but the argument is still required by the resource.

## Versioning

Pin the module with a git tag, as in `?ref=v0.1.0`. Tags follow semantic versioning; breaking changes bump the major version.

## Repository layout

The root of this repository is the account-level module described above, and its files stay at the top level. Organisation-level roles will join later as `modules/<name>` beside it, the first being `modules/kms` for customer-managed keys.

## License

MIT, see `LICENSE`.
