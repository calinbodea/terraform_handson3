variable "cidr_block" {}
variable "subnets" {
  type = map(list(string))
}

variable "ssh_key_name" {}

variable "instance_type" {}

variable "user_data" {

}