output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "Domain Name of the LBalancer"
}


output "elb_arn" {
  value = aws_lb.example.arn
}