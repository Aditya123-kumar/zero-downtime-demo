pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out project code...'
                checkout scm
            }
        }

        stage('Docker Build') {
            steps {
                echo 'Building Docker image...'
                sh 'docker build -t zero-downtime-demo-app:latest .'
            }
        }

        stage('Deploy') {
            steps {
                echo 'Starting zero-downtime deployment...'
                sh 'chmod +x deploy.sh'
                sh './deploy.sh'
            }
        }

        stage('Verify') {
            steps {
                echo 'Verifying application...'
                sh 'curl -f http://demo-nginx/ || exit 1'
            }
        }
    }

    post {
        success {
            echo 'Deployment completed successfully!'
        }

        failure {
            echo 'Deployment failed!'
        }
    }
}