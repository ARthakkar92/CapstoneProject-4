pipeline {
    agent any

    environment {
        AWS_REGION      = 'ap-south-1'
        ECR_REGISTRY    = '640928554403.dkr.ecr.ap-south-1.amazonaws.com'
        IMAGE_BACKEND   = "${ECR_REGISTRY}/akplacesolution-shopnow/backend"
        IMAGE_FRONTEND  = "${ECR_REGISTRY}/akplacesolution-shopnow/frontend"
        IMAGE_ADMIN     = "${ECR_REGISTRY}/akplacesolution-shopnow/admin"
        EKS_CLUSTER     = 'capstone-jenkins-eks'
        NAMESPACE       = 'shopnow'
    }

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

        stage('Build Backend Image') {
            steps {
                sh 'docker build -t $IMAGE_BACKEND:latest ./backend'
            }
        }

        stage('Build Frontend Image') {
            steps {
                sh 'docker build --build-arg USER_NAME="" -t $IMAGE_FRONTEND:latest ./frontend'
            }
        }

        stage('Build Admin Image') {
            steps {
                sh 'docker build --build-arg USER_NAME=admin -t $IMAGE_ADMIN:latest ./admin'
            }
        }

        stage('Push Images to ECR') {
            steps {
                sh '''
                    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
                    docker push $IMAGE_BACKEND:latest
                    docker push $IMAGE_FRONTEND:latest
                    docker push $IMAGE_ADMIN:latest
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION

                    kubectl apply -f k8s/namespace/namespace.yaml
                    kubectl apply -f k8s/mongo/mongo.yaml
                    kubectl apply -f k8s/backend/backend.yaml
                    kubectl apply -f k8s/frontend/frontend.yaml
                    kubectl apply -f k8s/admin/admin.yaml
                    kubectl apply -f k8s/ingress/ingress.yaml
                    kubectl apply -f k8s/hpa/backend-hpa.yaml
                    kubectl rollout restart deployment backend -n $NAMESPACE
                    kubectl rollout restart deployment frontend -n $NAMESPACE
                    kubectl rollout restart deployment admin -n $NAMESPACE

                    kubectl rollout status deployment backend -n $NAMESPACE --timeout=120s
                    kubectl rollout status deployment frontend -n $NAMESPACE --timeout=120s
                    kubectl rollout status deployment admin -n $NAMESPACE --timeout=120s
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    kubectl get pods -n $NAMESPACE
                    kubectl get ingress -n $NAMESPACE
                '''
            }
        }
    }
}
