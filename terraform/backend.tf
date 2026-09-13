terraform {
  backend "s3" {
    bucket       = "gamebred6296599796-terraform-state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}