pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Docker Test') {
            steps {
                powershell '''
                    Write-Host "Checking Docker..."
                    docker --version

                    Write-Host "Checking Docker Compose..."
                    docker compose version

                    Write-Host "Checking Docker containers..."
                    docker ps
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                powershell '''
                    Write-Host "Building Docker image..."
                    docker build -t zero-downtime-demo-app:latest .
                '''
            }
        }
    }

    post {
        success {
            echo 'GitHub, Docker and Docker build are working from Jenkins.'
        }

        failure {
            echo 'Pipeline failed.'
        }
    }
}