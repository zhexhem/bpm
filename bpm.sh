#!/bin/bash
VERSION=0.3.0
PACKAGE_DIR="${HOME}/.bpm/packages"
CONFIG_FILE="${HOME}/.bpm/config"
CACHE_DIR="${HOME}/.bpm/cache"
LOG_FILE="${HOME}/.bpm/bpm.log"
TEMP_DIR="${HOME}/.bpm/tmp"
REPO_FILE="${HOME}/.bpm/repositories"
BACKUP_DIR="${HOME}/.bpm/backups"
PLUGIN_DIR="${HOME}/.bpm/plugins"
HOOKS_DIR="${HOME}/.bpm/hooks"
LOCK_FILE="${HOME}/.bpm/lock"
PROFILE_FILE="${HOME}/.bpm/profile"

# Terminal capabilities using tput
setup_colors() {
    if [[ -t 1 ]] && [[ "$(tput colors 2>/dev/null)" -ge 8 ]] 2>/dev/null; then
        RED=$(tput setaf 1 2>/dev/null)
        GREEN=$(tput setaf 2 2>/dev/null)
        YELLOW=$(tput setaf 3 2>/dev/null)
        BLUE=$(tput setaf 4 2>/dev/null)
        MAGENTA=$(tput setaf 5 2>/dev/null)
        CYAN=$(tput setaf 6 2>/dev/null)
        BOLD=$(tput bold 2>/dev/null)
        NC=$(tput sgr0 2>/dev/null)
    else
        RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; NC=''
    fi
}

# Initialize colors
setup_colors

# Global variables
EXIT_CODE=0
OPERATION=""
START_TIME=$(date +%s)
INTERACTIVE=true
VERBOSE=false
FORCE=false
DRY_RUN=false
PROGRESS_BARS=true

# Initialize everything
init_dirs() {
    local dirs=(
        "${PACKAGE_DIR}" "${CACHE_DIR}" "${TEMP_DIR}"
        "${BACKUP_DIR}" "${PLUGIN_DIR}" "${HOOKS_DIR}"
        "$(dirname "${CONFIG_FILE}")" "$(dirname "${LOG_FILE}")"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
    done

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat >"${CONFIG_FILE}" <<'EOF'
# bpm configuration
PACKAGE_DIR=${HOME}/.bpm/packages
CACHE_DIR=${HOME}/.bpm/cache
LOG_FILE=${HOME}/.bpm/bpm.log
REPO_FILE=${HOME}/.bpm/repositories
BACKUP_DIR=${HOME}/.bpm/backups
PLUGIN_DIR=${HOME}/.bpm/plugins
HOOKS_DIR=${HOME}/.bpm/hooks

# Package settings
DEFAULT_REPO=https://zhexhem/bpm
INSTALL_TIMEOUT=300
RETRY_COUNT=3
PARALLEL_INSTALL=false
VERIFY_CHECKSUMS=true
AUTO_UPDATE=false
UPDATE_INTERVAL=86400

# Display settings
COLOR_OUTPUT=true
PROGRESS_BARS=true
CONFIRM_ACTIONS=true
EOF
    fi

    if [[ ! -f "${REPO_FILE}" ]]; then
        cat >"${REPO_FILE}" <<'EOF'
# bpm repositories
# Format: name url [priority]
official https://github.com/zhexhem/bpm
community https://community.bpm-repo.example.com 5
testing https://testing.bpm-repo.example.com 1
EOF
    fi

    # Create lock file if not exists
    touch "${LOCK_FILE}" 2>/dev/null || true
}

# Core utility functions
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local pid=$$
    echo "[${timestamp}] [${level}] [PID:${pid}] ${message}" >>"${LOG_FILE}"

    if [[ "${VERBOSE}" == "true" ]] || [[ "${level}" == "ERROR" ]] || [[ "${level}" == "WARNING" ]]; then
        case "${level}" in
            ERROR) echo "${RED}[ERROR]${NC} ${message}" >&2 ;;
            WARNING) echo "${YELLOW}[WARNING]${NC} ${message}" >&2 ;;
            INFO) echo "${BLUE}[INFO]${NC} ${message}" ;;
            DEBUG) [[ "${VERBOSE}" == "true" ]] && echo "${CYAN}[DEBUG]${NC} ${message}" ;;
        esac
    fi
}

echo_success() { 
    echo "${GREEN}✓${NC} $1"
}

echo_error() { 
    echo "${RED}✗${NC} $1" >&2
}

echo_warning() { 
    echo "${YELLOW}⚠${NC} $1"
}

echo_info() { 
    echo "${BLUE}ℹ${NC} $1"
}

echo_debug() { 
    [[ "${VERBOSE}" == "true" ]] && echo "${CYAN}🔍${NC} $1"
}

# Progress bar using tput for cursor control
progress_bar() {
    local current=$1
    local total=$2
    local width=50

    if [[ "${PROGRESS_BARS}" != "true" ]]; then
        echo -n "."
        return
    fi

    # Prevent division by zero
    if [[ ${total} -eq 0 ]]; then
        return
    fi

    local percent=$((current * 100 / total))
    local completed=$((percent * width / 100))
    local remaining=$((width - completed))

    printf "\r["
    printf "%${completed}s" | tr ' ' '='
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %3d%%" "${percent}"
}

# Lock management - FIXED
acquire_lock() {
    local lock_timeout=30
    local waited=0

    # Check if lock is held by another process
    while [[ -f "${LOCK_FILE}" ]]; do
        local lock_pid=$(cat "${LOCK_FILE}" 2>/dev/null)
        if [[ -z "${lock_pid}" ]] || ! kill -0 "${lock_pid}" 2>/dev/null; then
            # Lock file exists but process is dead - clean it up
            rm -f "${LOCK_FILE}"
            break
        fi
        
        if [[ ${waited} -ge ${lock_timeout} ]]; then
            echo_error "Timeout waiting for lock (held by PID ${lock_pid})"
            return 1
        fi
        sleep 1
        ((waited++))
    done

    echo $$ >"${LOCK_FILE}"
    return 0
}

release_lock() {
    rm -f "${LOCK_FILE}" 2>/dev/null
}

# Package installation check - ADDED
is_installed() {
    local package="$1"
    if [[ -d "${PACKAGE_DIR}/${package}" ]]; then
        return 0
    else
        return 1
    fi
}

# Hook system
run_hooks() {
    local hook_type="$1"
    local package="$2"
    local hook_dir="${HOOKS_DIR}/${hook_type}"

    if [[ -d "${hook_dir}" ]]; then
        for hook in "${hook_dir}"/*.sh; do
            if [[ -x "${hook}" ]]; then
                log "DEBUG" "Running hook: ${hook} for ${package}"
                "${hook}" "${package}" || {
                    echo_warning "Hook ${hook} failed for ${package}"
                    log "WARNING" "Hook ${hook} failed for ${package}"
                }
            fi
        done
    fi
}

# Package database operations
package_db_query() {
    local query="$1"
    local db_file="${CACHE_DIR}/package.db"

    if [[ ! -f "${db_file}" ]]; then
        return 1
    fi

    case "${query}" in
        "exists")
            grep -q "^${2}:" "${db_file}" 2>/dev/null
            ;;
        "get")
            grep "^${2}:" "${db_file}" | cut -d: -f2- 2>/dev/null
            ;;
        "list")
            cut -d: -f1 "${db_file}" 2>/dev/null
            ;;
    esac
}

update_package_db() {
    local repo_url="$1"
    local db_file="${CACHE_DIR}/package.db"
    
    echo_info "Updating package database from ${repo_url}"
    log "INFO" "Updating package database from ${repo_url}"
    
    # Simulate downloading database
    sleep 1
    
    cat >"${db_file}" <<'EOF'
PackageA:2.1.0:https://example.com/pkgA:Utility tool
PackageB:1.5.3:https://example.com/pkgB:Web framework
PackageC:0.9.8:https://example.com/pkgC:Data processor
PackageD:3.0.1:https://example.com/pkgD:Database tool
PackageE:4.2.0:https://example.com/pkgE:Cloud utilities
PackageF:1.0.7:https://example.com/pkgF:Security scanner
PackageG:2.3.1:https://example.com/pkgG:Log analyzer
PackageH:0.5.2:https://example.com/pkgH:Testing framework
PackageI:6.1.0:https://example.com/pkgI:Network tools
PackageJ:3.3.3:https://example.com/pkgJ:Graphics library
EOF
    
    echo_success "Package database updated"
}

# Dependency resolution
resolve_dependencies() {
    local package="$1"
    local deps_file="${CACHE_DIR}/${package}.deps"
    
    # Simulate dependency resolution
    echo_info "Resolving dependencies for ${package}"
    
    # Check if package has dependencies
    case "${package}" in
        PackageA)
            echo "PackageB PackageC"
            ;;
        PackageB)
            echo "PackageD"
            ;;
        PackageC)
            echo ""
            ;;
        PackageD)
            echo "PackageE PackageF"
            ;;
        *)
            echo ""
            ;;
    esac
}

check_dependency_conflicts() {
    local package="$1"
    local deps=($(resolve_dependencies "${package}"))
    local conflicts=()

    for dep in "${deps[@]}"; do
        if is_installed "${dep}"; then
            # Check version compatibility (simulated)
            local installed_version=$(get_package_version "${dep}")
            local required_version="1.0.0" # Simulated

            if ! version_satisfies "${installed_version}" "${required_version}"; then
                conflicts+=("${dep} (requires ${required_version}, have ${installed_version})")
            fi
        fi
    done

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo_error "Dependency conflicts found:"
        printf '  %s\n' "${conflicts[@]}"
        return 1
    fi

    return 0
}

# Version comparison
version_satisfies() {
    local version="$1"
    local requirement="$2"

    # Simple version comparison (semantic)
    local v1=(${version//./ })
    local v2=(${requirement//./ })

    for i in {0..2}; do
        local num1=${v1[i]:-0}
        local num2=${v2[i]:-0}

        if [[ ${num1} -lt ${num2} ]]; then
            return 1
        elif [[ ${num1} -gt ${num2} ]]; then
            return 0
        fi
    done

    return 0
}

# Get package version
get_package_version() {
    local package="$1"
    if [[ -f "${PACKAGE_DIR}/${package}/package.info" ]]; then
        source "${PACKAGE_DIR}/${package}/package.info"
        echo "${version:-0.0.0}"
    else
        echo "0.0.0"
    fi
}

# Transaction system
begin_transaction() {
    local transaction_id=$(date +%s%N 2>/dev/null || date +%s)$$
    local transaction_file="${TEMP_DIR}/transaction_${transaction_id}"

    echo "BEGIN" >"${transaction_file}"
    echo "ID: ${transaction_id}" >>"${transaction_file}"
    echo "OPERATION: ${OPERATION}" >>"${transaction_file}"
    echo "TIMESTAMP: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')" >>"${transaction_file}"

    echo "${transaction_id}"
}

commit_transaction() {
    local transaction_id="$1"
    local transaction_file="${TEMP_DIR}/transaction_${transaction_id}"
    
    if [[ -f "${transaction_file}" ]]; then
        echo "COMMIT" >>"${transaction_file}"
        log "INFO" "Transaction ${transaction_id} committed"
        rm -f "${transaction_file}"
        return 0
    else
        echo_error "Transaction ${transaction_id} not found"
        return 1
    fi
}

rollback_transaction() {
    local transaction_id="$1"
    local transaction_file="${TEMP_DIR}/transaction_${transaction_id}"
    
    if [[ -f "${transaction_file}" ]]; then
        echo "ROLLBACK" >>"${transaction_file}"
        log "WARNING" "Transaction ${transaction_id} rolled back"
        rm -f "${transaction_file}"
        return 0
    else
        echo_error "Transaction ${transaction_id} not found"
        return 1
    fi
}

# Cleanup on exit
cleanup() {
    release_lock
    # Clear any remaining progress bar
    echo
}

# Set trap for cleanup
trap cleanup EXIT

# Main script - example usage
main() {
    init_dirs
    echo_info "bpm version ${VERSION} initialized"
    echo_info "Using repository: https://github.com/zhexhem/bpm"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi