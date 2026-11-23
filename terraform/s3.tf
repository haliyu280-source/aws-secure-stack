data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "site" {
  bucket        = "secure-stack-assets-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # lab only: lets terraform destroy delete a bucket that still has files
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "site_page" {
  bucket       = aws_s3_bucket.site.id
  key          = "site.html"
  content      = "<h1>Secure stack</h1><p>Served by SERVER_NAME from a private S3 bucket, read with an IAM role. No access keys.</p>"
  content_type = "text/html"
}
