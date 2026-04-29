#!groovy

def AQA_REPO = params.AQA_REPO ?: "adoptium"
def AQA_BRANCH = params.AQA_BRANCH ?: "master"
def JDK_VERSIONS = params.JDK_VERSIONS.trim().split("\\s*,\\s*");
def PLATFORMS = params.PLATFORMS.trim().split("\\s*,\\s*");
def TARGETS = params.TARGETS.trim().split("\\s*,\\s*");
def LABEL = (params.LABEL) ?: ""

// Use BUILD_USER_ID if set and jdk-JDK_VERSIONS
def DEFAULT_SUFFIX = (env.BUILD_USER_ID) ? "${env.BUILD_USER_ID} - jdk-${params.JDK_VERSIONS}" : "jdk-${params.JDK_VERSIONS}"
def PIPELINE_DISPLAY_NAME = (params.PIPELINE_DISPLAY_NAME) ? "#${currentBuild.number} - ${params.PIPELINE_DISPLAY_NAME}" : "#${currentBuild.number} - ${DEFAULT_SUFFIX}"

timestamps{
    // Set the AQA_TEST_PIPELINE Jenkins job displayName
    currentBuild.setDisplayName(PIPELINE_DISPLAY_NAME)
    node(LABEL) {
        cleanWs disableDeferredWipeout: true, deleteDirs: true
        TIME_LIMIT =  params.TIME_LIMIT ? params.TIME_LIMIT.toInteger() : 1
        timeout(time: TIME_LIMIT, unit: 'HOURS') {
            // change openjdk-tests to aqa-tests
            sh "curl -Os https://raw.githubusercontent.com/${AQA_REPO}/aqa-tests/${AQA_BRANCH}/buildenv/jenkins/tapVerification/aqaTap.sh"
            sh "chmod 755 aqaTap.sh"
            JDK_VERSIONS.each { JDK_VERSION ->
                PLATFORMS.each { PLATFORM ->
                    String[] tokens = PLATFORM.split('_')
                    def os = tokens[1];
                    def arch = tokens[0];
                    if (arch.contains("x86-64")){
                        arch = "x64"
                    } else if (arch.contains("x86-32")) {
                        arch ="x86-32"
                    }

                    def filter = "*.tar.gz"
                    if (os.contains("windows")) {
                        filter = "*.zip"
                    }
                    def short_name = "hs"
                    def jdk_impl = "hotspot"
                    if (params.VARIANT == "openj9") {
                        short_name = "j9"
                        jdk_impl = params.VARIANT
                    }
                    def download_url = params.CUSTOMIZED_SDK_URL ? params.CUSTOMIZED_SDK_URL : ""
                    def sdk_resource_value = SDK_RESOURCE

                    if (SDK_RESOURCE == "customized" ) {
                        if (params.TOP_LEVEL_SDK_URL) {
                            // Try new Semeru release structure first (TAP files at root)
                            // example: <jenkins_url>/job/AQA_Test_Pipeline_Release/473/artifact/*zip*/archive.zip
                            // Then fall back to old structure with subdirectories
                            // example: <jenkins_url>/job/build-scripts/job/openjdk17-pipeline-IBM/354/artifact/target/linux/s390x/openj9/AQAvitTaps/*zip*/AQAvitTaps.zip

                            dir("${WORKSPACE}") {
                                env.PLATFORM = PLATFORM
                                def PLATFORM_DIR = params.PLATFORM_DIR ? "${params.PLATFORM_DIR}" : "${PLATFORM}"

                                // Try new structure (Semeru release - TAP files at root)
                                def new_structure_url = params.TOP_LEVEL_SDK_URL + "artifact/*zip*/archive.zip"
                                def old_structure_url = params.TOP_LEVEL_SDK_URL + "artifact/target/${os}/${arch}/${params.VARIANT}/AQAvitTaps/*zip*/AQAvitTaps.zip"

                                // Check which structure exists by trying to download
                                def download_success = false

                                // Try new structure first
                                if (params.CUSTOMIZED_SDK_URL_CREDENTIAL_ID) {
                                    withCredentials([usernamePassword(credentialsId: "${params.CUSTOMIZED_SDK_URL_CREDENTIAL_ID}", usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                                        def check_new = sh(script: "curl -u \$USERNAME:\$PASSWORD -I -L -s -o /dev/null -w '%{http_code}' '${new_structure_url}'", returnStdout: true).trim()
                                        if (check_new == "200") {
                                            echo "Using new Semeru release structure (TAP files at root)"
                                            download_url = new_structure_url
                                            // Download and extract all TAP files, then filter by platform
                                            sh "curl -u \$USERNAME:\$PASSWORD -L -o archive.zip '${download_url}'"
                                            sh "unzip -q archive.zip -d temp_extract || true"
                                            sh "mkdir -p AQAvitTapFiles/${PLATFORM_DIR}"
                                            // Find and copy TAP files for this platform
                                            sh """
                                                find temp_extract -name '*_${PLATFORM}.tap' -o -name '*_${PLATFORM}_*.tap' | while read file; do
                                                    cp "\$file" "AQAvitTapFiles/${PLATFORM_DIR}/" 2>/dev/null || true
                                                done
                                            """
                                            sh "rm -rf temp_extract archive.zip"
                                            download_success = true
                                        }
                                    }
                                } else {
                                    def check_new = sh(script: "curl -I -L -s -o /dev/null -w '%{http_code}' '${new_structure_url}'", returnStdout: true).trim()
                                    if (check_new == "200") {
                                        echo "Using new Semeru release structure (TAP files at root)"
                                        download_url = new_structure_url
                                        sh "curl -L -o archive.zip '${download_url}'"
                                        sh "unzip -q archive.zip -d temp_extract || true"
                                        sh "mkdir -p AQAvitTapFiles/${PLATFORM_DIR}"
                                        sh """
                                            find temp_extract -name '*_${PLATFORM}.tap' -o -name '*_${PLATFORM}_*.tap' | while read file; do
                                                cp "\$file" "AQAvitTapFiles/${PLATFORM_DIR}/" 2>/dev/null || true
                                            done
                                        """
                                        sh "rm -rf temp_extract archive.zip"
                                        download_success = true
                                    }
                                }

                                // If new structure didn't work, try old structure
                                if (!download_success) {
                                    echo "Using old structure (TAP files in subdirectories)"
                                    download_url = old_structure_url
                                    def aqaTapCmd = "${WORKSPACE}/aqaTap.sh -u ${download_url} -p ${PLATFORM_DIR}"
                                    if (params.CUSTOMIZED_SDK_URL_CREDENTIAL_ID) {
                                        withCredentials([usernamePassword(credentialsId: "${params.CUSTOMIZED_SDK_URL_CREDENTIAL_ID}", usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                                            sh "$aqaTapCmd"
                                        }
                                    } else {
                                        sh "$aqaTapCmd"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // archive
            sh "tar -cf - ./AQAvitTapFiles | (pigz -9 2>/dev/null || gzip -9) > AQAvitTapFiles.tar.gz"
            archiveArtifacts artifacts: "AQAvitTapFiles.tar.gz", fingerprint: true, allowEmptyArchive: false
        }
    }
}
