terraform {
  backend "s3" {
    bucket         = "capstone-devops-terraform-state-akplacesolution"
    key            = "capstone-jenkins/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "capstone-terraform-locks"
    encrypt        = true
  }
}
