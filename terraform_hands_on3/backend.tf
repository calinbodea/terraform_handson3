terraform {
  required_version = "~> 1.5.2"
  backend "s3" {
    region = "us-east-1"
    bucket = "my-s3-backend-bucket"
    key    = "terraform-handson4"
  }
}
