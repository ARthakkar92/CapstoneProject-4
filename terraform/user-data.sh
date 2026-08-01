#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1

echo "=== Updating system ==="
apt-get update -y
apt-get install -y fontconfig curl gnupg unzip git

echo "=== Installing Java 21 (Jenkins 2.568+ requirement) ==="
apt-get install -y openjdk-21-jre

echo "=== Adding Jenkins repo with current (2026) key ==="
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

echo "=== Installing Docker ==="
apt-get install -y docker.io
usermod -aG docker jenkins
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

echo "=== Installing AWS CLI v2 ==="
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

echo "=== Installing kubectl ==="
KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

echo "=== Starting Jenkins ==="
systemctl enable jenkins
systemctl start jenkins

echo "=== Bootstrap complete ==="
