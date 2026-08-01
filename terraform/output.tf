# outputs.tf
output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "ssh_command" {
  value = "ssh -i ${var.project_name}-key.pem ubuntu@${aws_instance.jenkins.public_ip}"
}