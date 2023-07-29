cidr_block = "10.0.10.0/24"

subnets = {
  public_1a  = ["10.0.10.0/26", "us-east-1a"]
  public_1b  = ["10.0.10.64/26", "us-east-1b"]
  private_1a = ["10.0.10.128/26", "us-east-1a"]
  private_1b = ["10.0.10.192/26", "us-east-1b"]
}

ssh_key_name = "tentek"

instance_type = "t2.micro"

user_data = "./test_user_data.sh"