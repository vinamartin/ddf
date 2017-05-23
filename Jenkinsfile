pipeline {
    agent none
    options {
        buildDiscarder(logRotator(numToKeepStr:'25'))
    }
    triggers {
        cron('H/15 * * * *')
    }
    stages {
        stage('Parallel Build') {
            steps{
                parallel(
                    linux: {
                        node('linux-large') {
                            echo sh(returnStdout: true, script: 'env')
                            checkout scm
                            withMaven(maven: 'M3', globalMavenSettingsConfig: 'default-global-settings', mavenSettingsConfig: 'codice-maven-settings') {
                                sh 'mvn install -DskipStatic=true -DskipTests=true -pl !distribution/docs'
                            }
                            timeout(time: 10, unit: 'MINUTES') {
                                withMaven(maven: 'M3', globalMavenSettingsConfig: 'default-global-settings', mavenSettingsConfig: 'codice-maven-settings') {
                                    sh 'mvn verify -Dit.test=TESTNAME#Test'
                                }
                            }
                        }
                    }
                )
            }
        }
    }
     post {
            failure {
                slackSend color: '#ea0017', message: "FAILURE: @vina @emily ${JOB_NAME} ${BUILD_NUMBER}. See the results here: ${BUILD_URL}"
            }
        }
}
