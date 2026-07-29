variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "network_interface_id" { type = string }
variable "ssh_allowed_cidrs" { type = list(string) }
variable "tags" {
  type    = map(string)
  default = {}
}
