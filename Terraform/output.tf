output "database_public_ip" {
  value = aws_instance.database.public_ip
}

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}

output "alb_public_ips" {
  value = split("\n", chomp(file("${path.module}/alb_ips.txt")))
}
