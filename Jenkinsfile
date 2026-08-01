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
            }
        }
    }
}
# test trigger
