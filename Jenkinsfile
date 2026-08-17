pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "Building Docker image..."
                    sudo docker build -t zero-downtime-demo-app:latest .
                '''
            }
        }

        stage('Zero Downtime Deployment') {
            steps {
                sh '''
                    chmod +x deploy.sh
                    sudo ./deploy.sh
                '''
            }
        }
    }

    post {
        success {
            echo 'Zero-downtime deployment completed successfully.'
        }

        failure {
            echo 'Deployment failed.'
        }
    }
}
