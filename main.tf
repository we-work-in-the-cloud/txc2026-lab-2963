# paste the workspace configuration here

# do not change after this line
variable "vpc_name" {
  description = "Name of your VPC"
}

variable "string_count" {
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "pci_compliance_tags" {
  type        = map(string)
  description = "Tags required for PCI compliance"
  default     = {}
}

resource "random_string" "random" {
  count            = var.string_count
  length           = 16
  special          = true
  override_special = "/@£$"
}

output "random" {
  value = [for r in random_string.random : r.result]
}

output "hello" {
  value = "world"
}

output "tags" {
  value = merge(var.pci_compliance_tags, var.tags)
}
