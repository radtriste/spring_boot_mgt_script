@Library("aiti-shared-libs")
import de.lv1871.aiti.monitoring.jenkins.apps.CopyRepoFilesJob

String APPS_FOLDER="/infra/apps"

CopyRepoFilesJob job

pipeline {
    agent any
    options {
        buildDiscarder(logRotator(numToKeepStr: '5'))
        disableConcurrentBuilds()
    }
    stages {
        stage("init"){
            steps{
                script{
                    job = new CopyRepoFilesJob(this)
                    job.init([remoteFolder: APPS_FOLDER])
                }
            }
        }
        stage("Copy files"){
            steps{
                script{
                    job.copyFiles()
                }
            }
        }
    }
    post {
        always {
            script{job.tearDown()}
        }
        failure {
            script{job.emailBuildResult('FAILED')}
        }
        unstable {
            script{job.emailBuildResult('UNSTABLE')}
        }
        changed {
            script{job.notifyChanged()}
        }
    }
}