data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  web_servers = {
    "web-1" = aws_subnet.public_a.id
    "web-2" = aws_subnet.public_b.id
  }
}

resource "aws_instance" "web" {
  for_each = local.web_servers

  ami                         = data.aws_ssm_parameter.ubuntu.insecure_value
  instance_type               = "t3.micro"
  subnet_id                   = each.value
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.web.name

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    bucket      = aws_s3_bucket.site.bucket
    region      = var.region
    server_name = each.key
  })
  user_data_replace_on_change = true

  tags = { Name = each.key }

  depends_on = [
    aws_s3_object.site_page,
    aws_iam_role_policy.s3_read,
    aws_cloudwatch_log_group.nginx_access,
    aws_cloudwatch_log_group.nginx_error,
  ]
}
