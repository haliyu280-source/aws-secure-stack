output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "web_security_group_id" {
  value = aws_security_group.web.id
}

output "site_url" {
  value = "http://${aws_lb.web.dns_name}"
}

output "web_public_ips" {
  value = { for name, server in aws_instance.web : name => server.public_ip }
}
