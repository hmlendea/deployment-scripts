#!/bin/bash
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  SCRIPT_DIRECTORY_PATH="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIRECTORY_PATH="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

DEPLOYMENT_CONFIGURATION_FILE_PATH="${SCRIPT_DIRECTORY_PATH}/config.conf"

function throw-exception {
    echo "[ERROR] $@"
    exit -1
}

function get-config-value {
    CONFIG_KEY="${1}"
    CONFIG_VALUE=$(grep "^${CONFIG_KEY}" "${DEPLOYMENT_CONFIGURATION_FILE_PATH}" | awk -F= '{print $2}')
    echo "${CONFIG_VALUE}"
}

CPU_ARCHITECTURE=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/  //g')
if [[ "${CPU_ARCHITECTURE}" == "x86_64" ]]; then
    PLATFORM="linux-x64"
elif [[ "${CPU_ARCHITECTURE}" == "aarch64" ]]; then
    PLATFORM="linux-arm64"
else
    PLATFORM="linux-arm"
fi

GITHUB_USERNAME=$(get-config-value "GitHubUsername")
GITHUB_ACCESS_TOKEN=$(get-config-value "GitHubAccessToken")
GITHUB_REPOSITORY=${1} && shift

[ -z "${GITHUB_USERNAME}" ] && throw-exception "The GitHub username cannot be empty"
[ -z "${GITHUB_ACCESS_TOKEN}" ] && throw-exception "The GitHub access token cannot be empty"
[ -z "${GITHUB_REPOSITORY}" ] && throw-exception "The GitHub repository name cannot be empty"

if [ -n "${SERVICE_INSTANCE_NAME}" ]; then
    SERVICE_NAME="${GITHUB_REPOSITORY}_${SERVICE_INSTANCE_NAME}"
else
    SERVICE_NAME="${GITHUB_REPOSITORY}"
fi

DEPLOYMENT_ROOT_DIRECTORY=$(get-config-value "DeploymentRootDirectory")
DEPLOYMENT_APPSETTINGS_FILE_PATH="${DEPLOYMENT_ROOT_DIRECTORY}/appsettings.csv"
SERVICE_ROOT_DIRECTORY="${DEPLOYMENT_ROOT_DIRECTORY}/${SERVICE_NAME}"
SERVICE_BINARIES_DIRECTORY="${SERVICE_ROOT_DIRECTORY}/bin"
SERVICE_TEMPORARY_DIRECTORY="${SERVICE_ROOT_DIRECTORY}/tmp"
SERVICE_VERSION_FILE_LOCATION="${SERVICE_ROOT_DIRECTORY}/version"
SERVICE_LAUNCHER_FILE_LOCATION="${SERVICE_ROOT_DIRECTORY}/start"

NEEDS_UPDATE=0

echo "> Ensuring the file structure..."
[ ! -d "${SERVICE_ROOT_DIRECTORY}" ]        && mkdir -p "${SERVICE_ROOT_DIRECTORY}"
[ ! -d "${SERVICE_BINARIES_DIRECTORY}" ]    && mkdir -p "${SERVICE_BINARIES_DIRECTORY}"
[ ! -d "${SERVICE_TEMPORARY_DIRECTORY}" ]   && mkdir -p "${SERVICE_TEMPORARY_DIRECTORY}"
[ ! -f "${SERVICE_VERSION_FILE_LOCATION}" ] && touch "${SERVICE_VERSION_FILE_LOCATION}"

if [ -z $(cat "${SERVICE_VERSION_FILE_LOCATION}") ] || \
   [ ! "$(ls -A ${SERVICE_BINARIES_DIRECTORY})" ]   || \
   [ ! -f "${SERVICE_LAUNCHER_FILE_LOCATION}" ]     ; then
    echo "  > Service not installed!"
    echo "    > Update required!"
    NEEDS_UPDATE=1
fi

function getLatestReleaseVersion() {
    curl \
        --silent \
        --header "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
        "https://api.github.com/repos/${GITHUB_USERNAME}/${GITHUB_REPOSITORY}/releases/latest" | \
            grep "tag_name" | \
            sed 's/.*: \"v\([^\"]*\).*/\1/g'
}

echo "> Retrieving version information..."
LATEST_VERSION=$(getLatestReleaseVersion)

if [[ "${LATEST_VERSION}" == "Not Found" ]]; then
    throw-exception "Cannot find a stable version to download"
fi

echo "  > Latest version: $LATEST_VERSION"

if [ "${NEEDS_UPDATE}" -eq "0" ]; then
    CURRENT_VERSION=$(cat "${SERVICE_VERSION_FILE_LOCATION}")
    echo "  > Current version: ${CURRENT_VERSION}"

    if [[ "${LATEST_VERSION}" > "${CURRENT_VERSION}" ]]; then
        echo "  > Update required!"
        NEEDS_UPDATE=1
    fi
fi

function download-package {
    echo "  > Downloading the latest version..."

    local PACKAGE_FILE_NAME="${GITHUB_REPOSITORY}_${LATEST_VERSION}_${PLATFORM}.zip"
    local PACKAGE_FILE_PATH="${SERVICE_TEMPORARY_DIRECTORY}/${PACKAGE_FILE_NAME}"

    local ASSET_ID=$(curl \
                        -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
                        -H "Accept: application/vnd.github.v3.raw" \
                        -s "https://api.github.com/repos/${GITHUB_USERNAME}/${GITHUB_REPOSITORY}/releases/tags/v${LATEST_VERSION}" | \
                    jq ".assets | map(select(.name == \"${PACKAGE_FILE_NAME}\"))[0].id")

    if [ -z "${ASSET_ID}" ] || [ "${ASSET_ID}" = "null" ]; then
        throw-exception "Failed to retrieve the GitHub Asset ID for ${PACKAGE_FILE_NAME}"
    fi

    wget \
        --quiet \
        --auth-no-challenge \
        --header='Accept:application/octet-stream' \
        "https://${GITHUB_ACCESS_TOKEN}:@api.github.com/repos/${GITHUB_USERNAME}/${GITHUB_REPOSITORY}/releases/assets/${ASSET_ID}" \
        --output-document "${PACKAGE_FILE_PATH}" 2>/dev/null

    if [ ! -f "${PACKAGE_FILE_PATH}" ] \
    || [ $(du "${PACKAGE_FILE_PATH}" | awk '{print $1}') -eq 4 ]; then
        throw-exception "Failed to download the service package!"
    fi
}

function extract-package {
    echo "  > Extracting the package..."

    PACKAGE_FILE_NAME="${GITHUB_REPOSITORY}_${LATEST_VERSION}_${PLATFORM}.zip"
    PACKAGE_FILE_PATH="${SERVICE_TEMPORARY_DIRECTORY}/${PACKAGE_FILE_NAME}"
    IS_SUCCESS=0

    if [ -f "${PACKAGE_FILE_PATH}" ]; then
        unzip -qq "${PACKAGE_FILE_PATH}" -d "${SERVICE_BINARIES_DIRECTORY}" && IS_SUCCESS=1
        rm "${PACKAGE_FILE_PATH}"
    fi

    if [ $IS_SUCCESS == 0 ]; then
        throw-exception "Failed to extract the service package!"
    fi

    printf "${LATEST_VERSION}" > "${SERVICE_VERSION_FILE_LOCATION}"
}

if [ "${NEEDS_UPDATE}" -eq "1" ]; then
    echo "> Updating the service..."


    if [ "$(ls -A ${SERVICE_BINARIES_DIRECTORY})" ]; then
        echo "  > Removing the existing version..."
        rm -rf "${SERVICE_BINARIES_DIRECTORY}"
        mkdir "${SERVICE_BINARIES_DIRECTORY}"
    fi

    download-package
    extract-package
fi

SERVICE_EXECUTABLE_FILE_NAME=$(ls "${SERVICE_BINARIES_DIRECTORY}" | grep ".deps.json" | sed 's/\.deps\.json$//g')
SERVICE_EXECUTABLE_FILE_LOCATION="${SERVICE_BINARIES_DIRECTORY}/${SERVICE_EXECUTABLE_FILE_NAME}"

echo "> Setting up application settings..."

for APPSETTING in $(cat "${DEPLOYMENT_APPSETTINGS_FILE_PATH}"); do
    APPSETTING_APP=$(echo "${APPSETTING}" | awk -F, '{print $1}')
    APPSETTING_MOD=$(echo "${APPSETTING}" | awk -F, '{print $2}')
    APPSETTING_KEY=$(echo "${APPSETTING}" | awk -F, '{print $3}')
    APPSETTING_VAL=$(echo "${APPSETTING}" | sed 's/^[^,]*,[^,]*,[^,]*,//g')

    APPSETTING_VAL=$(echo "${APPSETTING_VAL}" | sed 's/%SERVICE_NAME%/'${SERVICE_NAME}'/g')

    if [[ "${APPSETTING_APP}" != "ALL" ]] && \
       [[ "${APPSETTING_APP}" != "${SERVICE_NAME}" ]] && \
       [[ "${APPSETTING_APP}" != "${GITHUB_REPOSITORY}" ]]; then
        continue
    fi

    for APPSETTINGS_FILE in $(find "${SERVICE_BINARIES_DIRECTORY}" -type f -name "appsettings*.json") ; do
        if [[ "${APPSETTING_MOD}" == "by-key" ]]; then
            sed 's|\"'${APPSETTING_KEY}'\": *\"*[^\"]*\"*|\"'${APPSETTING_KEY}'\": \"'${APPSETTING_VAL}'\"|g' -i "${APPSETTINGS_FILE}"
        elif [[ "${APPSETTING_MOD}" == "by-val" ]]; then
            sed 's|"\[*'${APPSETTING_KEY}'\]*"|"'${APPSETTING_VAL}'"|g' -i "${APPSETTINGS_FILE}"
        fi
    done
done

if [ ! -f "${SERVICE_LAUNCHER_FILE_LOCATION}" ]; then
    echo "> Building the launcher script..."

    echo "  > Determining the application type..."
    DOTNET_DEPS_FILE_LOCATION="${SERVICE_BINARIES_DIRECTORY}/${SERVICE_EXECUTABLE_FILE_NAME}.deps.json"
    APP_TYPE="UNKNOWN"

    if [ -f "${DOTNET_DEPS_FILE_LOCATION}" ]; then
        APP_TYPE="DOTNET_CORE"

        if [ $(grep -c "Microsoft\.AspNetCore\.App" "${DOTNET_DEPS_FILE_LOCATION}") -ge 1 ]; then
            APP_TYPE="ASP_DOTNET_CORE"
        fi
    fi
    echo "  > Application type: ${APP_TYPE}"

    echo "  > Writing the script..."
    echo "#!/bin/bash" > "${SERVICE_LAUNCHER_FILE_LOCATION}"
    echo "PREVIOUS_DIRECTORY_LOCATION=\"$(pwd)\"" >> "${SERVICE_LAUNCHER_FILE_LOCATION}"
    echo "cd \"${SERVICE_BINARIES_DIRECTORY}\"" >> "${SERVICE_LAUNCHER_FILE_LOCATION}"
    if [[ "${APP_TYPE}" = "ASP_DOTNET_CORE" ]]; then
        PORT_NUMBER=${1} && shift

        [[ ${PORT_NUMBER} =~ [^0-9]+ ]] && throw-exception "The specified port number is invalid: ${PORT_NUMBER}"
        [ -z "${PORT_NUMBER}" ] && throw-exception "The port number cannot be empty"

        printf "ASPNETCORE_URLS=\"http://*:${PORT_NUMBER}\" " >> "${SERVICE_LAUNCHER_FILE_LOCATION}"
    fi
    echo "\"${SERVICE_EXECUTABLE_FILE_LOCATION}\" \$@" >> "${SERVICE_LAUNCHER_FILE_LOCATION}"
    echo "cd \"\${PREVIOUS_DIRECTORY_LOCATION}\"" >> "${SERVICE_LAUNCHER_FILE_LOCATION}"
    chmod +x "${SERVICE_LAUNCHER_FILE_LOCATION}"
fi

[ ! -x "${SERVICE_EXECUTABLE_FILE_LOCATION}" ]  && chmod +x "${SERVICE_EXECUTABLE_FILE_LOCATION}"
[ ! -x "${SERVICE_LAUNCHER_FILE_LOCATION}" ]    && chmod +x "${SERVICE_LAUNCHER_FILE_LOCATION}"

echo "> Launching the service..."
sh "${SERVICE_LAUNCHER_FILE_LOCATION}" $@
