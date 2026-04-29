#!/usr/bin/env bash

################################################################################
# Script to collect TAP files for Semeru CE AQAvit Verification
# This script helps collect TAP files for the 9 required targets:
# - sanity.functional, extended.functional, special.functional
# - sanity.openjdk, extended.openjdk
# - sanity.system, extended.system
# - sanity.perf, extended.perf
#
# TAP files are organized in platform-specific folders:
# ibm-semeru-certified-jdk_<platform>_<version>.tap/
################################################################################

set -eo pipefail

# Configuration
JENKINS_URL="https://hyc-runtimes-jenkins.swg-devops.com"
ARTIFACTORY_URL="https://na.artifactory.swg-devops.com/ui/repos/tree/General/sys-rt-generic-local/hyc-runtimes-jenkins.swg-devops.com/AQAvit/openj9"
OUTPUT_DIR="SemeruCE_AQAvit_TAPs"
RELEASE_VERSION=""
SEMERU_VERSION="" # e.g., 11.0.31.0, 17.0.13.0, 21.0.5.0, 25.0.1.0
JDK_VERSIONS=()
PLATFORMS=()
BUILD_NUMBERS=()
JENKINS_JOB_NAME=""
DOWNLOAD_METHOD="jenkins" # jenkins or artifactory
JENKINS_CREDENTIALS=""

# Required AQAvit targets
REQUIRED_TARGETS=(
    "sanity.functional"
    "extended.functional"
    "special.functional"
    "sanity.openjdk"
    "extended.openjdk"
    "sanity.system"
    "extended.system"
    "sanity.perf"
    "extended.perf"
)

# Platform mapping: internal name -> folder name
declare -A PLATFORM_MAP=(
    ["x86-64_linux"]="x64_linux"
    ["aarch64_linux"]="aarch64_linux"
    ["ppc64le_linux"]="ppc64le_linux"
    ["ppc64_aix"]="ppc64_aix"
    ["s390x_linux"]="s390x_linux"
)

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Collect TAP files for Semeru CE AQAvit Verification

OPTIONS:
    -r, --release VERSION       Release version (e.g., April2026)
    -v, --semeru-version VER    Semeru version (e.g., 11.0.31.0)
    -j, --jdk-versions VERSIONS Comma-separated JDK versions (e.g., 11,17,21,25)
    -p, --platforms PLATFORMS   Comma-separated platforms (default: all supported)
    -b, --build-numbers NUMS    Comma-separated Jenkins build numbers
    -n, --job-name NAME         Jenkins job name for TAP collection
    -m, --method METHOD         Download method: jenkins or artifactory (default: jenkins)
    -o, --output DIR            Output directory (default: SemeruCE_AQAvit_TAPs)
    -u, --jenkins-url URL       Jenkins URL (default: $JENKINS_URL)
    -c, --credentials USER:PASS Jenkins credentials (username:password)
    -h, --help                  Show this help message

EXAMPLES:
    # Collect TAPs for JDK 11 from Jenkins
    $0 -r April2026 -v 11.0.31.0 -j 11 -b 100 -n "build-scripts/job/openjdk11-pipeline"

    # Collect TAPs for multiple JDK versions
    $0 -r April2026 -v 11.0.31.0 -j 11,17,21,25 -b 100,101,102,103

    # Collect with credentials
    $0 -r April2026 -v 11.0.31.0 -j 11 -b 100 -c "username:password"

OUTPUT STRUCTURE:
    SemeruCE_AQAvit_TAPs/
    ├── ibm-semeru-certified-jdk_x64_linux_11.0.31.0.tap/
    │   ├── Test_openjdk11_j9_sanity.functional_x86-64_linux.tap
    │   ├── Test_openjdk11_j9_extended.functional_x86-64_linux.tap
    │   └── ...
    ├── ibm-semeru-certified-jdk_aarch64_linux_11.0.31.0.tap/
    ├── ibm-semeru-certified-jdk_ppc64le_linux_11.0.31.0.tap/
    ├── ibm-semeru-certified-jdk_ppc64_aix_11.0.31.0.tap/
    └── ibm-semeru-certified-jdk_s390x_linux_11.0.31.0.tap/

REQUIRED AQAVIT TARGETS:
$(printf "    - %s\n" "${REQUIRED_TARGETS[@]}")

SUPPORTED PLATFORMS:
    - x86-64_linux (folder: x64_linux)
    - aarch64_linux
    - ppc64le_linux
    - ppc64_aix
    - s390x_linux

EOF
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release)
                RELEASE_VERSION="$2"
                shift 2
                ;;
            -v|--semeru-version)
                SEMERU_VERSION="$2"
                shift 2
                ;;
            -j|--jdk-versions)
                IFS=',' read -ra JDK_VERSIONS <<< "$2"
                shift 2
                ;;
            -p|--platforms)
                IFS=',' read -ra PLATFORMS <<< "$2"
                shift 2
                ;;
            -b|--build-numbers)
                IFS=',' read -ra BUILD_NUMBERS <<< "$2"
                shift 2
                ;;
            -n|--job-name)
                JENKINS_JOB_NAME="$2"
                shift 2
                ;;
            -m|--method)
                DOWNLOAD_METHOD="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -u|--jenkins-url)
                JENKINS_URL="$2"
                shift 2
                ;;
            -c|--credentials)
                JENKINS_CREDENTIALS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$RELEASE_VERSION" ]]; then
        error "Release version is required. Use -r or --release"
    fi

    if [[ -z "$SEMERU_VERSION" ]]; then
        error "Semeru version is required. Use -v or --semeru-version"
    fi

    if [[ ${#JDK_VERSIONS[@]} -eq 0 ]]; then
        error "JDK versions are required. Use -j or --jdk-versions"
    fi

    # Set default platforms if not specified
    if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
        PLATFORMS=("x86-64_linux" "aarch64_linux" "ppc64le_linux" "ppc64_aix" "s390x_linux")
    fi

    # Validate download method
    if [[ "$DOWNLOAD_METHOD" != "jenkins" && "$DOWNLOAD_METHOD" != "artifactory" ]]; then
        error "Invalid download method: $DOWNLOAD_METHOD. Use 'jenkins' or 'artifactory'"
    fi

    # Validate Jenkins parameters if using Jenkins method
    if [[ "$DOWNLOAD_METHOD" == "jenkins" ]]; then
        if [[ ${#BUILD_NUMBERS[@]} -eq 0 ]]; then
            error "Build numbers are required for Jenkins method. Use -b or --build-numbers"
        fi
    fi
}

get_platform_folder_name() {
    local platform=$1
    echo "${PLATFORM_MAP[$platform]:-$platform}"
}

create_directory_structure() {
    log "Creating directory structure..."
    mkdir -p "$OUTPUT_DIR"

    for jdk_version in "${JDK_VERSIONS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            local folder_platform=$(get_platform_folder_name "$platform")
            local dir="$OUTPUT_DIR/ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap"
            mkdir -p "$dir"
            log "Created: $dir"
        done
    done
}

download_from_jenkins() {
    local jdk_version=$1
    local platform=$2
    local build_number=$3

    log "Downloading TAPs for JDK${jdk_version} ${platform} from Jenkins build ${build_number}..."

    # Determine the artifact path based on platform
    local arch="${platform%%_*}"
    local os="${platform##*_}"

    # Convert arch for Jenkins path
    if [[ "$arch" == "x86-64" ]]; then
        arch="x64"
    fi

    local artifact_path="target/${os}/${arch}/openj9/AQAvitTaps/*zip*/AQAvitTaps.zip"
    local download_url="${JENKINS_URL}/job/${JENKINS_JOB_NAME}/${build_number}/artifact/${artifact_path}"

    local folder_platform=$(get_platform_folder_name "$platform")
    local output_dir="$OUTPUT_DIR/ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap"
    local temp_file="${output_dir}/AQAvitTaps_${build_number}.zip"

    log "Download URL: $download_url"

    # Download with or without credentials
    if [[ -n "$JENKINS_CREDENTIALS" ]]; then
        curl -u "$JENKINS_CREDENTIALS" -L -o "$temp_file" "$download_url" || {
            log "Warning: Failed to download from $download_url"
            return 1
        }
    else
        curl -L -o "$temp_file" "$download_url" || {
            log "Warning: Failed to download from $download_url"
            return 1
        }
    fi

    # Extract TAP files
    log "Extracting TAP files to $output_dir..."
    unzip -q "$temp_file" -d "$output_dir" || {
        log "Warning: Failed to extract $temp_file"
        return 1
    }

    # Move TAP files from nested directory if needed
    if [[ -d "$output_dir/AQAvitTaps" ]]; then
        mv "$output_dir/AQAvitTaps"/*.tap "$output_dir/" 2>/dev/null || true
        rm -rf "$output_dir/AQAvitTaps"
    fi

    # Clean up zip file
    rm -f "$temp_file"

    log "Successfully downloaded and extracted TAPs to $output_dir"
    return 0
}

download_from_artifactory() {
    local jdk_version=$1
    local platform=$2

    log "Downloading TAPs for JDK${jdk_version} ${platform} from Artifactory..."

    local folder_platform=$(get_platform_folder_name "$platform")
    local output_dir="$OUTPUT_DIR/ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap"

    # Construct Artifactory path
    local artifact_path="${ARTIFACTORY_URL}/jdk${jdk_version}/${platform}"

    log "Artifactory path: $artifact_path"
    log "Output directory: $output_dir"
    log "Note: You may need to manually download from Artifactory UI"
    log "Please visit: $artifact_path"
}

collect_taps() {
    log "Starting TAP collection for Semeru CE ${RELEASE_VERSION}..."

    create_directory_structure

    if [[ "$DOWNLOAD_METHOD" == "jenkins" ]]; then
        local build_idx=0
        for jdk_version in "${JDK_VERSIONS[@]}"; do
            for platform in "${PLATFORMS[@]}"; do
                if [[ $build_idx -lt ${#BUILD_NUMBERS[@]} ]]; then
                    download_from_jenkins "$jdk_version" "$platform" "${BUILD_NUMBERS[$build_idx]}"
                    ((build_idx++))
                else
                    log "Warning: Not enough build numbers provided for all JDK/platform combinations"
                    break 2
                fi
            done
        done
    else
        for jdk_version in "${JDK_VERSIONS[@]}"; do
            for platform in "${PLATFORMS[@]}"; do
                download_from_artifactory "$jdk_version" "$platform"
            done
        done
    fi
}

verify_tap_files() {
    log "=========================================="
    log "Verifying TAP files for all platforms..."
    log "=========================================="

    local all_verified=true

    for jdk_version in "${JDK_VERSIONS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            local folder_platform=$(get_platform_folder_name "$platform")
            local tap_dir="$OUTPUT_DIR/ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap"

            log ""
            log "Checking: ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap"
            log "----------------------------"

            if [[ ! -d "$tap_dir" ]]; then
                log "  [ERROR] Directory not found: $tap_dir"
                all_verified=false
                continue
            fi

            for target in "${REQUIRED_TARGETS[@]}"; do
                local tap_files=$(find "$tap_dir" -name "*${target}*.tap" 2>/dev/null)
                local tap_count=$(echo "$tap_files" | grep -c "\.tap$" || echo "0")

                if [[ $tap_count -eq 0 ]]; then
                    log "  [MISSING] ${target}"
                    all_verified=false
                else
                    log "  [FOUND] ${target} (${tap_count} file(s))"
                    echo "$tap_files" | while read -r file; do
                        if [[ -n "$file" ]]; then
                            log "    - $(basename "$file")"
                        fi
                    done
                fi
            done
        done
    done

    log ""
    log "=========================================="
    if [[ "$all_verified" == true ]]; then
        log "✓ All required TAP files verified!"
    else
        log "✗ Some TAP files are missing. Please review the output above."
    fi
    log "=========================================="
}

generate_summary_report() {
    log "Generating summary report..."

    local report_file="$OUTPUT_DIR/collection_summary_${RELEASE_VERSION}.txt"

    cat > "$report_file" << EOF
Semeru CE AQAvit TAP Collection Summary
========================================
Release Version: ${RELEASE_VERSION}
Semeru Version: ${SEMERU_VERSION}
Collection Date: $(date)
JDK Versions: ${JDK_VERSIONS[*]}
Platforms: ${PLATFORMS[*]}
Download Method: ${DOWNLOAD_METHOD}

Required AQAvit Targets (9):
$(printf "  - %s\n" "${REQUIRED_TARGETS[@]}")

TAP Files by Platform:
EOF

    for jdk_version in "${JDK_VERSIONS[@]}"; do
        echo "" >> "$report_file"
        echo "JDK ${jdk_version}:" >> "$report_file"
        for platform in "${PLATFORMS[@]}"; do
            local folder_platform=$(get_platform_folder_name "$platform")
            local tap_dir="$OUTPUT_DIR/ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap"
            if [[ -d "$tap_dir" ]]; then
                local tap_count=$(find "$tap_dir" -name "*.tap" 2>/dev/null | wc -l)
                echo "  ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap: ${tap_count} TAP files" >> "$report_file"

                # List all TAP files
                find "$tap_dir" -name "*.tap" 2>/dev/null | while read -r file; do
                    echo "    - $(basename "$file")" >> "$report_file"
                done
            else
                echo "  ibm-semeru-certified-jdk_${folder_platform}_${SEMERU_VERSION}.tap: Directory not found" >> "$report_file"
            fi
        done
    done

    log "Summary report saved to: $report_file"
}

main() {
    parse_args "$@"

    log "=========================================="
    log "Semeru CE AQAvit TAP Collection"
    log "Release: ${RELEASE_VERSION}"
    log "Semeru Version: ${SEMERU_VERSION}"
    log "JDK Versions: ${JDK_VERSIONS[*]}"
    log "Platforms: ${PLATFORMS[*]}"
    log "Method: ${DOWNLOAD_METHOD}"
    log "=========================================="

    collect_taps
    verify_tap_files
    generate_summary_report

    log ""
    log "=========================================="
    log "TAP collection complete!"
    log "Output directory: $OUTPUT_DIR"
    log "=========================================="
}

main "$@"

# Made with Bob
