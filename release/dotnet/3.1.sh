#!/bin/bash

VERSION="${1}"

if [ -z "${VERSION}" ]; then
    echo "PLEASE PROVIDE A VERSION !!!"
    exit 1
fi

APP_NAME=$(git remote -v | tail -1 | sed 's|.*/\([^/]*\)\.git.*|\1|')

if [ -f *.sln ]; then
    MAIN_PROJECT=$(ls *.sln | head -n 1 | xargs cat | grep "^Project" | head -n 1 | awk -F"=" '{print $2}' | awk -F"," '{print $1}' | sed -e 's/\"*//g' -e 's/\s*//g')
    cd "${MAIN_PROJECT}"
fi

PROJECT_SOURCE_DIR="$(pwd)"
BIN_RELEASE_DIR="${PROJECT_SOURCE_DIR}/bin/Release"
PUBLISH_DIR="${BIN_RELEASE_DIR}/.publish-script-output"

function package {
    local ARCH="${1}"
    local OUTPUT_DIR="${PUBLISH_DIR}/${ARCH}"
    local OUTPUT_FILE="${BIN_RELEASE_DIR}/${APP_NAME}_${VERSION}_${ARCH}.zip"

    echo "Packaging \"${OUTPUT_DIR}\" to \"${OUTPUT_FILE}\""

    [ -f "${OUTPUT_FILE}" ] && rm "${OUTPUT_FILE}"

    cd "${OUTPUT_DIR}" || exit
    zip -q -9 -r "${OUTPUT_FILE}" .
    cd "${PROJECT_SOURCE_DIR}" || exit
}

function dotnet-pub {
    ARCH="${1}"
    OUTPUT_DIR="${PUBLISH_DIR}/${ARCH}"

    [ ! -d "${OUTPUT_DIR}" ] && mkdir -p "${OUTPUT_DIR}"
    cd "${PROJECT_SOURCE_DIR}" || exit
    
    dotnet publish -c Release -r "${ARCH}" -o "${OUTPUT_DIR}" --self-contained=true /p:TrimUnusedDependencies=true /p:LinkDuringPublish=true
}

function prepare {
    mkdir -p "${PUBLISH_DIR}"

    echo "Adding the temporary NuGet packages"
    dotnet add package Microsoft.Packaging.Tools.Trimming --version 1.1.0-preview1-26619-01
    #dotnet add package ILLink.Tasks --version 0.1.5-preview-1841731 --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json
}

function cleanup {
    echo "Removing the temporary NuGet packages"
    dotnet remove package Microsoft.Packaging.Tools.Trimming
    #dotnet remove package ILLink.Tasks

    echo "Cleaning build output"
    rm -rf "${PUBLISH_DIR}"
}

prepare

dotnet-pub win-x64
package win-x64

dotnet-pub linux-x64
package linux-x64

dotnet-pub osx-x64
package osx-x64

cleanup

