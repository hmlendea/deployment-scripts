#!/bin/bash

VERSION="${1}"

if [ -z "${VERSION}" ]; then
    echo "ERROR: Please specify a version"
    exit 1
fi

APP_NAME=$(git remote -v | tail -1 | sed 's|.*/\([^/]*\)\.git.*|\1|')
SOLUTION_DIR=$(pwd)

if [ -f *.sln ]; then
    MAIN_PROJECT_NAME=$(ls *.sln | head -n 1 | xargs cat | grep "^Project" | head -n 1 | awk -F"=" '{print $2}' | awk -F"," '{print $1}' | sed -e 's/\"*//g' -e 's/\s*//g')
    MAIN_PROJECT_DIR="${SOLUTION_DIR}/${MAIN_PROJECT_NAME}"
else
    MAIN_PROJECT_DIR="${SOLUTION_DIR}"
fi

MAIN_PROJECT_FILE=$(ls "${MAIN_PROJECT_DIR}"/*.csproj | head -n 1)
cd "${MAIN_PROJECT_DIR}"

BINARY_FILE_LABEL=$(cat "${MAIN_PROJECT_FILE}" | grep "RootNamespace" | sed 's/[^>]*>\([^<]*\).*/\1/g')
BIN_RELEASE_DIR="${MAIN_PROJECT_DIR}/bin/Release"
PUBLISH_DIR="${BIN_RELEASE_DIR}/.publish-script-output"

function package {
    local ARCH="${1}"
    local OUTPUT_DIR="${PUBLISH_DIR}/${ARCH}"
    local OUTPUT_FILE=""
    local FILES_COUNT=0

    rm "${OUTPUT_DIR}"/*.pdb
    FILES_COUNT=$(ls -1q "${OUTPUT_DIR}" | wc -l)

    if [ ${FILES_COUNT} -eq 1 ]; then
        BINARY_FILE=$(ls "${OUTPUT_DIR}"/*)
        BINARY_FILE_NAME=$(basename "${BINARY_FILE}")
        OUTPUT_FILE=$(sed 's/'"${BINARY_FILE_LABEL}"'/'"${APP_NAME}"'_'"${VERSION}"'_'"${ARCH}"'/g' <<< "${BINARY_FILE_NAME}")
        OUTPUT_FILE="${BIN_RELEASE_DIR}/${OUTPUT_FILE}"

        echo "Copying \"${BINARY_FILE_NAME}\" to \"${OUTPUT_FILE}\""

        cp "${BINARY_FILE}" "${OUTPUT_FILE}"
    else
        OUTPUT_FILE="${BIN_RELEASE_DIR}/${APP_NAME}_${VERSION}_${ARCH}.zip"

        echo "Packaging \"${OUTPUT_DIR}\" as \"${OUTPUT_FILE}\""
        [ -f "${OUTPUT_FILE}" ] && rm "${OUTPUT_FILE}"

        cd "${OUTPUT_DIR}" || exit
        zip -q -9 -r "${OUTPUT_FILE}" .
        cd "${MAIN_PROJECT_DIR}" || exit
    fi
}

function dotnet-pub {
    local ARCH="${1}"
    local OUTPUT_DIR="${PUBLISH_DIR}/${ARCH}"

    [ ! -d "${OUTPUT_DIR}" ] && mkdir -p "${OUTPUT_DIR}"
    cd "${MAIN_PROJECT_DIR}" || exit

    dotnet publish \
        --configuration Release \
        --runtime "${ARCH}" \
        --output "${OUTPUT_DIR}" \
        --self-contained true \
        /p:TrimUnusedDependencies=true \
        /p:LinkDuringPublish=true
}

function prepare {
    mkdir -p "${PUBLISH_DIR}"

    sed -i 's/\(\s*\)\(<TargetFramework>.*\)/\1\2\n\1<PublishTrimmed>true<\/PublishTrimmed> <!-- RELEASE_SCRIPT_TEMP -->/g' "${MAIN_PROJECT_FILE}"
}

function cleanup {
    echo "Cleaning the build output"
    rm -rf "${PUBLISH_DIR}"

    sed -i '/.*<!-- RELEASE_SCRIPT_TEMP.*/d' "${MAIN_PROJECT_FILE}"
}

function build-release {
    local ARCH="${1}"

    dotnet-pub "${ARCH}"
    package "${ARCH}"
}

prepare

build-release linux-arm
build-release linux-arm64
build-release linux-x64
build-release osx-arm64
build-release osx-x64
build-release win-arm64
build-release win-x64

cleanup
