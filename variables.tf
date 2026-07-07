variable "integration_id" {
  type        = string
  description = "The Formal cloud integration id (a typeid, e.g. cloud-integration_01hxxxxxxxxxxxxxxxxxxxxxxx). The part after the underscore is used to derive resource names."

  validation {
    condition     = can(regex("_[a-z0-9]{26}$", var.integration_id))
    error_message = "integration_id must be a typeid ending in an underscore followed by a 26-character suffix."
  }
}

variable "formal_role_arn" {
  type        = string
  description = "The per-integration AWS IAM role ARN that Formal presents. The workload identity pool provider only trusts this exact role, and Formal's AWS account id is derived from it."

  validation {
    condition     = can(regex("^arn:aws:(iam|sts)::[0-9]{12}:", var.formal_role_arn))
    error_message = "formal_role_arn must be a valid AWS IAM/STS ARN."
  }
}

variable "project_id" {
  type        = string
  description = "The Google Cloud project id to connect to Formal."
}

variable "roles" {
  type        = list(string)
  description = "IAM roles to grant Formal's service account on the project, driven by the capabilities you enable (resource discovery, log delivery). Grant only what you need; an empty list establishes the connection with no project access."
  default     = []
}
