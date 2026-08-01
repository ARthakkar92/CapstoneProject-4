pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                echo 'Repository checked out successfully'
            }
        }
        stage('Verify Tools') {
            steps {
                sh 'docker --version'
                sh 'aws --version'
                sh 'kubectl version --client'
                sh 'terraform -version'
            }
        }
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init -input=false'
                }
            }
        }
        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan -input=false'
                }
            }
        }
    }
}
