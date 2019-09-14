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

function write-line {
    printf "$@\n" >> "${SERVICE_FILE_PATH}"
}


write-line "Description=${SERVICE_NAME} service"
write-line "After=network.target"
write-line ""
write-line "[Service]"
write-line "WorkingDirectory=${DEPLOYMENT_ROOT_DIRECTORY_PATH}"
write-line "ExecStart=${SERVICE_BOOT_FILE_PATH} ${SERVICE_NAME} ${OTHER_ARGS}"
write-line "User=${SUDO_USER}"
write-line "MemoryAccounting=yes"
write-line "MemoryMax=200M"
write-line "CPUQuota=60%"
write-line ""
write-line "[Install]"
write-line "WantedBy=multi-user.target"

chmod +x "${SERVICE_FILE_PATH}"

systemctl daemon-reload
systemctl enable "${SERVICE_FILE_NAME}"
systemctl restart "${SERVICE_FILE_NAME}"
