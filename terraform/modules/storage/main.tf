#this is my main bucket,storage for all 3 zones.
resource "aws_s3_bucket" "data_lake" {
  bucket        = var.data_lake_bucket_name
  force_destroy = true
}

#enabling the versioning of that main bucket
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration { status = "Enabled" }
}

#version enabling protects our s3 data,it keeps track of it,
#we can time travel but we also have to keep in mind about the storage cost it comes with,so we set up a retention period of 7 days

resource "aws_s3_bucket_lifecycle_configuration" "data_lake_lifecycle" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

#bucket side encryption,I used the algo AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#I dont want public traffic from internet to enter my s3 network
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#this is my script bucket,where i store all my glue script,will refer to this position later on while actually creating the glue job resource
resource "aws_s3_bucket" "scripts" {
  bucket        = var.scripts_bucket_name
  force_destroy = true
}

#same thing,we enabled versioning
resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  versioning_configuration { status = "Enabled" }
}

#encrytion
resource "aws_s3_bucket_server_side_encryption_configuration" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#block public 
resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket                  = aws_s3_bucket.scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


#this is the bucket which contains my actual source json files which i'll be ingesting later on
resource "aws_s3_bucket" "source_data" {
  bucket        = var.source_data_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "source_data" {
  bucket = aws_s3_bucket.source_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source_data" {
  bucket = aws_s3_bucket.source_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "source_data" {
  bucket = aws_s3_bucket.source_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}