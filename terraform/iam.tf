# Trust policy: only the EC2 service may use this role
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "web-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# CloudWatch agent permissions (AWS managed policy)
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Least privilege: read one bucket, nothing else
data "aws_iam_policy_document" "s3_read" {
  statement {
    sid       = "ListThisBucketOnly"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    sid       = "ReadObjectsInThisBucketOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_read" {
  name   = "read-site-bucket"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.s3_read.json
}

resource "aws_iam_instance_profile" "web" {
  name = "web-server-profile"
  role = aws_iam_role.web.name
}
