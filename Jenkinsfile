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
                    $docker = "C:\\Users\\CEREBRENT PC\\AppData\\Local\\Programs\\DockerDesktop\\resources\\bin\\docker.exe"

                    Write-Host "Checking Docker..."
                    & $docker --version

                    Write-Host "Checking Docker containers..."
                    & $docker ps
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                powershell '''
                    $docker = "C:\\Users\\CEREBRENT PC\\AppData\\Local\\Programs\\DockerDesktop\\resources\\bin\\docker.exe"

                    Write-Host "Building Docker image..."
                    & $docker build -t zero-downtime-demo-app:latest .
                '''
            }
        }

        stage('Zero Downtime Deployment') {
            steps {
                powershell '''
                    Write-Host "Starting zero downtime deployment..."

                    powershell -ExecutionPolicy Bypass -File .\\deploy.ps1
                '''
            }
        }
    }

    post {
        success {
            echo 'Zero downtime deployment completed successfully.'
        }

        failure {
            echo 'Pipeline failed.'
        }
    }
}
