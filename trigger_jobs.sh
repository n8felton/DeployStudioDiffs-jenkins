#!/bin/sh

CLI_JAR_PATH="$HOME/Downloads/jenkins-cli.jar"
JOBNAME=DeployStudioDiffs-Nightly
if [ -z "${JENKINS_URL}" ]; then
    echo "Please set JENKINS_URL in the environment to use this script!"
    exit 1
fi

BUILD_SPECS=(
    1.6.3
    1.6.4-NB131015
    1.6.4-NB131027
    1.6.4-NB131113
    1.6.4-NB140121
    1.6.4-NB140123
    1.6.4-NB140126
    1.6.4-NB140130
    1.6.4-NB140206
    1.6.4-NB140227
    1.6.4-NB140303
    1.6.4-NB140309
    1.6.4-NB140326
    1.6.4-NB140327
    1.6.4
    1.6.5
    1.6.6
    1.6.7
    1.6.8
    1.6.9
    1.6.10
    1.6.11
    1.6.12
    1.6.13
    1.6.14
    1.6.15
)

for SPEC in "${BUILD_SPECS[@]}"; do
    java -jar "${CLI_JAR_PATH}" build "${JOBNAME}" -p "BUILD_SPEC=${SPEC}"
done
