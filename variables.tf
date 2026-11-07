variable "org" {
  description = "Your Osier organisation slug (the one in your Osier URL)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.org))
    error_message = "org must be a slug: lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "project" {
  description = "The Osier project slug these roles trust."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.project))
    error_message = "project must be a slug: lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "stacks" {
  description = "Narrow the roles to these stacks of the project. Empty means every stack."
  type        = list(string)
  default     = []
}

variable "split_apply_role" {
  description = "Create a separate apply role. Plan runs execute repository code before approval, so the plan role stays read-only. Set false only if you accept that plan-time code holds apply permissions."
  type        = bool
  default     = true
}

variable "plan_policy_arns" {
  description = "Managed policy ARNs attached to the plan role when split_apply_role is true. Ignored otherwise."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

variable "policy_arns" {
  description = "Managed policy ARNs attached to the apply role when split_apply_role is true, or to the single role otherwise. Use least privilege."
  type        = list(string)
  default     = []
}

variable "role_name" {
  description = "Name of the plan (or single) role. Defaults to osier-<project>. The apply role is <role_name>-apply."
  type        = string
  default     = null
}

variable "create_provider" {
  description = "Create the IAM OIDC identity provider. Set false when the account already has one for this issuer (for example a second project in the same account)."
  type        = bool
  default     = true
}

variable "issuer" {
  description = "Host of the Osier OIDC issuer, without a scheme."
  type        = string
  default     = "osier.dev"

  validation {
    condition     = !can(regex("://", var.issuer)) && !can(regex("/", var.issuer))
    error_message = "issuer must be a bare host such as osier.dev, with no scheme or path."
  }
}
