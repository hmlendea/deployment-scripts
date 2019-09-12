#!/bin/bash
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  SCRIPT_DIRECTORY_PATH="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIRECTORY_PATH="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

SERVICE_NAME="$1"
OTHER_ARGS="${*:2}"

DEPLOYMENT_CONFIGURATION_FILE_PATH="${SCRIPT_DIRECTORY_PATH}/config.conf"

function throw-exception {
    echo "[ERROR] $@"
    exit -1
}

function get-config-value {
    CONFIG_KEY="$1"
    CONFIG_VALUE=$(grep "^${CONFIG_KEY}" "${DEPLOYMENT_CONFIGURATION_FILE_PATH}" | awk -F= '{print $2}')
    echo "${CONFIG_VALUE}"
}

DEPLOYMENT_ROOT_DIRECTORY_PATH=$(get-config-value "DeploymentRootDirectory")

[ ! -d "${DEPLOYMENT_ROOT_DIRECTORY_PATH}" ] && throw-exception "The deployment root directory does not exist!"

SERVICE_BOOT_FILE_PATH="${SCRIPT_DIRECTORY_PATH}/start-service.sh"
SERVICE_FILE_NAME="${SERVICE_NAME}.service"
SERVICE_FILE_PATH="/lib/systemd/system/${SERVICE_FILE_NAME}"

[ -f "${SERVICE_FILE_PATH}" ] && rm "${SERVICE_FILE_PATH}"

touch "${SERVICE_FILE_PATH}"

printf "[Unit]\n" >> "${SERVICE_FILE_PATH}"
printf "Description=${SERVICE_NAME} service\n" >> "${SERVICE_FILE_PATH}"
printf "After=network.target\n" >> "${SERVICE_FILE_PATH}"
printf "\n" >> "${SERVICE_FILE_PATH}"
printf "[Service]\n" >> "${SERVICE_FILE_PATH}"
printf "WorkingDirectory=${DEPLOYMENT_ROOT_DIRECTORY_PATH}\n" >> "${SERVICE_FILE_PATH}"
printf "ExecStart=${SERVICE_BOOT_FILE_PATH} ${SERVICE_NAME} ${OTHER_ARGS}\n" >> "${SERVICE_FILE_PATH}"
printf "User=${SUDO_USER}\n" >> "${SERVICE_FILE_PATH}"
printf "\n" >> "${SERVICE_FILE_PATH}"
printf "[Install]\n" >> "${SERVICE_FILE_PATH}"
printf "WantedBy=multi-user.target\n" >> "${SERVICE_FILE_PATH}"

chmod +x "${SERVICE_FILE_PATH}"

systemctl daemon-reload
systemctl enable "${SERVICE_FILE_NAME}"
systemctl restart "${SERVICE_FILE_NAME}"
