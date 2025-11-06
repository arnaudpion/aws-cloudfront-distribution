output "app_url" {
  description = "URL used to reach the web app"
  value       = aws_lb.alb.dns_name
}

output "bastion_ip_address" {
  description = "IP Address used to reach the bastion host"
  value       = aws_instance.bastion_vm.public_ip
}