#!/bin/bash

VERSION="${1}"

if [ -z "${VERSION}" ]; then
    echo "ERROR: Please specify a version"
    exit 1
fi

APP_NAME=$(git remote -v | tail -1 | sed 's|.*/\([^/]*\)\.git.*|\1|')
SOLUTION_DIR=$(pwd)

if [ -f *.sln ]; then
    MAIN_PROJECT_NAME=$(ls *.sln | head -n 1 | xargs cat | grep "^Project" | grep -v 'UnitTests' | head -n 1 | awk -F"=" '{print $2}' | awk -F"," '{print $1}' | sed -e 's/\"*//g' -e 's/\s*//g')
    MAIN_PROJECT_DIR="${SOLUTION_DIR}/${MAIN_PROJECT_NAME}"
elif [ -f *.slnx ]; then
    MAIN_PROJECT_NAME=$(ls *.slnx | head -n 1 | xargs grep 'Path=' | grep -v 'UnitTests' | head -n 1 | sed 's/.*Path="\([^"]*\)".*/\1/' | awk -F'/' '{print $1}')
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

    rm -f "${OUTPUT_DIR}"/*.pdb
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
        /p:Version="${VERSION}" \
        /p:IncludeNativeLibrariesForSelfExtract=true \
        /p:DebugType=None \
        /p:DebugSymbols=false \
        /p:LinkDuringPublish=true
}

function prepare {
    mkdir -p "${PUBLISH_DIR}"
}

function remove-gitignored-data-files {
    local ARCH="${1}"
    local DATA_DIR="${PUBLISH_DIR}/${ARCH}/Data"
    local SOURCE_DATA_DIR="${MAIN_PROJECT_DIR}/Data"

    if [ ! -d "${DATA_DIR}" ]; then
        return
    fi

    while IFS= read -r -d '' DATA_FILE; do
        local SOURCE_FILE="${SOURCE_DATA_DIR}/$(basename "${DATA_FILE}")"

        if git -C "${SOLUTION_DIR}" check-ignore -q "${SOURCE_FILE}" 2>/dev/null; then
            echo "Removing gitignored data file \"${DATA_FILE}\""
            rm "${DATA_FILE}"
        fi
    done < <(find "${DATA_DIR}" -maxdepth 1 \( -name '*.json' -o -name '*.xml' \) -print0)
}

function cleanup {
    echo "Cleaning the build output"
    rm -rf "${PUBLISH_DIR}"
}

function build-release {
    local ARCH="${1}"

    dotnet-pub "${ARCH}"
    remove-gitignored-data-files "${ARCH}"
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
