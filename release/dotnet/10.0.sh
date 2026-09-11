#!/bin/bash

set -euo pipefail

readonly SUCCESS_EXIT_CODE=0
readonly ERROR_EXIT_CODE=1
readonly DEFAULT_PUBLISH_CONCURRENCY=2
readonly ZIP_COMPRESSION_OPTION='-9'
readonly VERSION="${1:-}"
readonly -a RUNTIME_IDENTIFIERS=(
    'linux-arm'
    'linux-arm64'
    'linux-x64'
    'osx-arm64'
    'osx-x64'
    'win-arm64'
    'win-x64'
)

if [[ -z "${VERSION}" ]]; then
    echo 'ERROR: Please specify a version.' >&2
    exit "${ERROR_EXIT_CODE}"
fi

if [[ ! "${VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
    echo 'ERROR: The version must be a semantic version, such as 1.2.3 or 1.2.3-beta.1.' >&2
    exit "${ERROR_EXIT_CODE}"
fi

readonly ASSEMBLY_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.0"
readonly PUBLISH_CONCURRENCY="${PUBLISH_CONCURRENCY:-${DEFAULT_PUBLISH_CONCURRENCY}}"

if [[ ! "${PUBLISH_CONCURRENCY}" =~ ^[1-9][0-9]*$ ]]; then
    echo 'ERROR: PUBLISH_CONCURRENCY must be a positive integer.' >&2
    exit "${ERROR_EXIT_CODE}"
fi

readonly APPLICATION_NAME="$(
    git remote -v |
        tail -n 1 |
        sed 's|.*/\([^/]*\)\.git.*|\1|'
)"
readonly SOLUTION_DIRECTORY="${PWD}"

shopt -s nullglob

declare -a SOLUTION_FILES=("${SOLUTION_DIRECTORY}"/*.sln)
declare -a EXTENDED_SOLUTION_FILES=("${SOLUTION_DIRECTORY}"/*.slnx)
declare -a PROJECT_FILES=("${SOLUTION_DIRECTORY}"/*.csproj)

MAIN_PROJECT_FILE=''

if (( ${#SOLUTION_FILES[@]} > 0 )); then
    MAIN_PROJECT_RELATIVE_PATH="$(
        awk -F ',' '
            /^Project/ && /\.csproj"/ && $0 !~ /UnitTests/ {
                project_path = $2
                gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", project_path)
                gsub(/\\/, "/", project_path)
                print project_path
                exit
            }
        ' "${SOLUTION_FILES[0]}"
    )"
    MAIN_PROJECT_FILE="${SOLUTION_DIRECTORY}/${MAIN_PROJECT_RELATIVE_PATH}"
elif (( ${#EXTENDED_SOLUTION_FILES[@]} > 0 )); then
    MAIN_PROJECT_RELATIVE_PATH="$(
        awk '
            /Path="[^"]*\.csproj"/ && $0 !~ /UnitTests/ {
                project_path = $0
                sub(/^.*Path="/, "", project_path)
                sub(/".*$/, "", project_path)
                gsub(/\\/, "/", project_path)
                print project_path
                exit
            }
        ' "${EXTENDED_SOLUTION_FILES[0]}"
    )"
    MAIN_PROJECT_FILE="${SOLUTION_DIRECTORY}/${MAIN_PROJECT_RELATIVE_PATH}"
elif (( ${#PROJECT_FILES[@]} > 0 )); then
    MAIN_PROJECT_FILE="${PROJECT_FILES[0]}"
else
    echo 'ERROR: No .sln, .slnx, or .csproj file was discovered.' >&2
    exit "${ERROR_EXIT_CODE}"
fi

if [[ ! -f "${MAIN_PROJECT_FILE}" ]]; then
    echo "ERROR: The main project file \"${MAIN_PROJECT_FILE}\" does not exist." >&2
    exit "${ERROR_EXIT_CODE}"
fi

readonly MAIN_PROJECT_FILE
readonly MAIN_PROJECT_DIRECTORY="${MAIN_PROJECT_FILE%/*}"

BINARY_FILE_LABEL="$(
    awk '
        {
            root_namespace_line = $0

            if (sub(/^.*<RootNamespace>/, "", root_namespace_line) &&
                sub(/<\/RootNamespace>.*$/, "", root_namespace_line)) {
                print root_namespace_line
                exit
            }
        }
    ' "${MAIN_PROJECT_FILE}"
)"

if [[ -z "${BINARY_FILE_LABEL}" ]]; then
    BINARY_FILE_LABEL="${MAIN_PROJECT_FILE##*/}"
    BINARY_FILE_LABEL="${BINARY_FILE_LABEL%.csproj}"
fi

readonly BINARY_FILE_LABEL
readonly BINARY_RELEASE_DIRECTORY="${MAIN_PROJECT_DIRECTORY}/bin/Release"
readonly PUBLISH_DIRECTORY="${BINARY_RELEASE_DIRECTORY}/.publish-script-output"
readonly PUBLISH_ARTIFACTS_DIRECTORY="${PUBLISH_DIRECTORY}/.artifacts"

function package {
    local -r RUNTIME_IDENTIFIER="${1}"
    local -r OUTPUT_DIRECTORY="${PUBLISH_DIRECTORY}/${RUNTIME_IDENTIFIER}"
    local -a DEBUG_SYMBOL_FILES=("${OUTPUT_DIRECTORY}"/*.pdb)
    local -a OUTPUT_FILES
    local OUTPUT_FILE=''

    if (( ${#DEBUG_SYMBOL_FILES[@]} > 0 )); then
        rm -f "${DEBUG_SYMBOL_FILES[@]}"
    fi

    OUTPUT_FILES=("${OUTPUT_DIRECTORY}"/*)

    if (( ${#OUTPUT_FILES[@]} == 1 )); then
        local -r BINARY_FILE="${OUTPUT_FILES[0]}"
        local -r BINARY_FILE_NAME="${BINARY_FILE##*/}"
        local -r OUTPUT_FILE_NAME="${BINARY_FILE_NAME//${BINARY_FILE_LABEL}/${APPLICATION_NAME}_${VERSION}_${RUNTIME_IDENTIFIER}}"
        OUTPUT_FILE="${BINARY_RELEASE_DIRECTORY}/${OUTPUT_FILE_NAME}"

        printf 'Copying "%s" to "%s".\n' "${BINARY_FILE_NAME}" "${OUTPUT_FILE}"
        cp "${BINARY_FILE}" "${OUTPUT_FILE}"
    else
        OUTPUT_FILE="${BINARY_RELEASE_DIRECTORY}/${APPLICATION_NAME}_${VERSION}_${RUNTIME_IDENTIFIER}.zip"

        printf 'Packaging "%s" as "%s".\n' "${OUTPUT_DIRECTORY}" "${OUTPUT_FILE}"
        rm -f "${OUTPUT_FILE}"

        (
            cd "${OUTPUT_DIRECTORY}"
            zip -q "${ZIP_COMPRESSION_OPTION}" -r "${OUTPUT_FILE}" .
        )
    fi
}

function dotnet_publish {
    local -r RUNTIME_IDENTIFIER="${1}"
    local -r OUTPUT_DIRECTORY="${PUBLISH_DIRECTORY}/${RUNTIME_IDENTIFIER}"
    local -r ARTIFACTS_DIRECTORY="${PUBLISH_ARTIFACTS_DIRECTORY}/${RUNTIME_IDENTIFIER}"

    mkdir -p "${OUTPUT_DIRECTORY}"

    dotnet publish "${MAIN_PROJECT_FILE}" \
        --configuration Release \
        --runtime "${RUNTIME_IDENTIFIER}" \
        --output "${OUTPUT_DIRECTORY}" \
        --artifacts-path "${ARTIFACTS_DIRECTORY}" \
        --self-contained true \
        /p:Version="${VERSION}" \
        /p:AssemblyVersion="${ASSEMBLY_VERSION}" \
        /p:FileVersion="${ASSEMBLY_VERSION}" \
        /p:InformationalVersion="${VERSION}" \
        /p:IncludeNativeLibrariesForSelfExtract=true \
        /p:DebugType=None \
        /p:DebugSymbols=false \
        /p:LinkDuringPublish=true
}

function prepare {
    rm -rf "${PUBLISH_DIRECTORY}"
    mkdir -p "${PUBLISH_DIRECTORY}"
}

function remove_gitignored_data_files {
    local -r RUNTIME_IDENTIFIER="${1}"
    local -r DATA_DIRECTORY="${PUBLISH_DIRECTORY}/${RUNTIME_IDENTIFIER}/Data"
    local -r SOURCE_DATA_DIRECTORY="${MAIN_PROJECT_DIRECTORY}/Data"
    local DATA_FILE
    local SOURCE_FILE=''

    if [[ ! -d "${DATA_DIRECTORY}" ]]; then
        return
    fi

    while IFS= read -r -d '' DATA_FILE; do
        SOURCE_FILE="${SOURCE_DATA_DIRECTORY}/${DATA_FILE##*/}"

        if git -C "${SOLUTION_DIRECTORY}" check-ignore -q "${SOURCE_FILE}" 2>/dev/null; then
            printf 'Removing gitignored data file "%s".\n' "${DATA_FILE}"
            rm "${DATA_FILE}"
        fi
    done < <(find "${DATA_DIRECTORY}" -maxdepth 1 \( -name '*.json' -o -name '*.xml' \) -print0)
}

function cleanup {
    echo 'Cleaning the build output.'
    rm -rf "${PUBLISH_DIRECTORY}"
}

function build_release {
    local -r RUNTIME_IDENTIFIER="${1}"

    dotnet_publish "${RUNTIME_IDENTIFIER}"
    remove_gitignored_data_files "${RUNTIME_IDENTIFIER}"
    package "${RUNTIME_IDENTIFIER}"
}

function wait_for_publishes {
    local PROCESS_IDENTIFIER
    local EXIT_CODE="${SUCCESS_EXIT_CODE}"

    for PROCESS_IDENTIFIER in "${@}"; do
        if ! wait "${PROCESS_IDENTIFIER}"; then
            EXIT_CODE="${ERROR_EXIT_CODE}"
        fi
    done

    return "${EXIT_CODE}"
}

function build_releases {
    local RUNTIME_IDENTIFIER
    local -a PROCESS_IDENTIFIERS=()

    for RUNTIME_IDENTIFIER in "${RUNTIME_IDENTIFIERS[@]}"; do
        build_release "${RUNTIME_IDENTIFIER}" &
        PROCESS_IDENTIFIERS+=("$!")

        if (( ${#PROCESS_IDENTIFIERS[@]} >= ${PUBLISH_CONCURRENCY} )); then
            wait_for_publishes "${PROCESS_IDENTIFIERS[@]}"
            PROCESS_IDENTIFIERS=()
        fi
    done

    if (( ${#PROCESS_IDENTIFIERS[@]} > 0 )); then
        wait_for_publishes "${PROCESS_IDENTIFIERS[@]}"
    fi
}

prepare
build_releases

cleanup
