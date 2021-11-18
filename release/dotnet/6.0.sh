#!/bin/bash

VERSION="${1}"

if [ -z "${VERSION}" ]; then
    echo "ERROR: Please specify a version"
    exit 1
fi

APP_NAME=$(git remote -v | tail -1 | sed 's|.*/\([^/]*\)\.git.*|\1|')

if [ -f *.sln ]; then
    MAIN_PROJECT=$(ls *.sln | head -n 1 | xargs cat | grep "^Project" | head -n 1 | awk -F"=" '{print $2}' | awk -F"," '{print $1}' | sed -e 's/\"*//g' -e 's/\s*//g')
    cd "${MAIN_PROJECT}"
fi

RELEASE_DIR_RELATIVE="bin/Release"
PUBLISH_DIR_RELATIVE="${RELEASE_DIR_RELATIVE}/publish-script-output"
RELEASE_DIR="$(pwd)/${RELEASE_DIR_RELATIVE}"
PUBLISH_DIR="$(pwd)/${PUBLISH_DIR_RELATIVE}"

function package {
    local ARCH="${1}"
    local OUTPUT_DIR="${PUBLISH_DIR}/${ARCH}"
    local OUTPUT_FILE="${RELEASE_DIR}/${APP_NAME}_${VERSION}_${ARCH}.zip"

    echo "Packaging \"${OUTPUT_DIR}\" to \"${OUTPUT_FILE}\""

    [ -f "${OUTPUT_FILE}" ] && rm "${OUTPUT_FILE}"

    cd "${OUTPUT_DIR}" || exit
    zip -q -9 -r "${OUTPUT_FILE}" .
    cd - || exit
}

function dotnet-pub {
    local ARCH="${1}"
    local OUTPUT_DIR="${PUBLISH_DIR_RELATIVE}/${ARCH}"

    dotnet publish \
        --configuration Release \
        --runtime "${ARCH}" \
        --output "${OUTPUT_DIR}" \
        --self-contained true \
        /p:TrimUnusedDependencies=true \
        /p:LinkDuringPublish=true
}

function cleanup {
    echo "Cleaning build output"
    rm -rf "${PUBLISH_DIR}"
}

function build-release {
    local ARCH="${1}"

    dotnet-pub "${ARCH}"
    package "${ARCH}"
}

build-release linux-arm
build-release linux-arm64
build-release linux-x64
build-release osx-arm64
build-release osx-x64
build-release win-arm64
build-release win-x64

cleanup
