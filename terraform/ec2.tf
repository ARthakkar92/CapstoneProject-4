# ec2.tf
resource "aws_instance" "jenkins" {
  ami                         = "ami-0c809520a0d652e03"
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  key_name                    = aws_key_pair.jenkins_key.key_name
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.name

  user_data = file("${path.module}/user-data.sh")

  root_block_device {
    volume_size = 20
  }

  tags = { Name = "${var.project_name}-jenkins-server" }
}