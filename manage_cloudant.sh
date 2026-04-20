#!/usr/bin/env bash

# A robust script to backup and restore Cloudant databases to a local
# directory and optionally upload to an S3-compatible object store.

# Exit on error, treat unset variables as errors, and fail on pipe errors.
set -euo pipefail

# Enable exporting of all variables
set -o allexport
# Load environment variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found."
    exit 1
fi

# --- CONFIGURATION ---
# It is highly recommended to use a separate, git-ignored file (e.g., .env)
# to manage these variables. You can load it with `source .env` before
# running the script.

# Cloudant URL with credentials. Must be set in your environment.
# Example: export COUCH_URL="https://user:pass@account.cloudant.com"
: "${COUCH_URL:?ERROR: COUCH_URL environment variable is not set.}"

# List of databases to back up.
# Can be overridden by setting the environment variable.
# Example: export DATABASES="db1 db2 db3"
DBS_TO_BACKUP=${DATABASES:-"github_actions_jobs github_app_repos_allowlist github_app_users"}
# Convert space-separated string to array
read -r -a DATABASES <<< "$DBS_TO_BACKUP"

# Environment name (e.g., prod, staging).
ENV="${ENV:-prod}"

# Local backup root directory.
LOCAL_BACKUP_ROOT="${LOCAL_BACKUP_ROOT:-backup}"

# --- S3 UPLOAD CONFIGURATION ---
# Set to "true" to enable S3 upload.
UPLOAD_TO_S3="${UPLOAD_TO_S3:-false}"
S3_BUCKET="${S3_BUCKET:gha-cloudant-db-backup}"
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-http://s3.us-east.cloud-object-storage.appdomain.cloud}"

# ==============================================================================
# SCRIPT LOGIC - DO NOT EDIT BELOW THIS LINE
# ==============================================================================

# --- Logging Functions ---
# Provides standardized and colored output.
log_info() {
    printf "\e[34m[INFO]\e[0m %s\n" "$@"
}

log_warn() {
    printf "\e[33m[WARN]\e[0m %s\n" "$@"
}

log_error() {
    printf "\e[31m[ERROR]\e[0m %s\n" "$@" >&2
}

# --- Utility Functions ---
# Exits the script with an error message.
die() {
    log_error "$@"
    exit 1
}

# Checks for the presence of required command-line tools.
check_dependencies() {
    log_info "Checking for required tools..."
    for cmd in npm curl couchbackup couchrestore; do
        if ! command -v "$cmd" &>/dev/null; then
            log_warn "Command '$cmd' not found. It will be installed if it's part of @cloudant/couchbackup."
            # The install function will be called later to handle it
        fi
    done
    if [[ "${UPLOAD_TO_S3}" == "true" ]] && ! command -v aws &>/dev/null; then
        die "'aws' CLI is not found but S3 upload is enabled. Please install it."
    fi
    log_info "Dependency check complete."
}

# Installs @cloudant/couchbackup if not already present.
install_couch_tools() {
    if ! command -v couchbackup &>/dev/null || ! command -v couchrestore &>/dev/null; then
        log_info "Installing @cloudant/couchbackup globally via npm..."
        if ! npm install -g @cloudant/couchbackup; then
            die "Failed to install @cloudant/couchbackup. Please check npm permissions."
        fi
        log_info "Installation successful."
    else
        log_info "@cloudant/couchbackup tools are already installed."
    fi
}

# --- Core Functions ---

# Backs up the specified databases to a timestamped local directory.
backup_databases() {
    log_info "Starting backup process..."
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local backup_dir="${LOCAL_BACKUP_ROOT}/${ENV}/${ENV}_${timestamp}"

    mkdir -p "${backup_dir}" || die "Failed to create backup directory: ${backup_dir}"
    log_info "Backup directory created: ${backup_dir}"

    for db in "${DATABASES[@]}"; do
        log_info "--- Backing up database: ${db} ---"
        local backup_file="${backup_dir}/${db}-backup.txt"
        local log_file="${backup_dir}/${db}-backup.log"

        if couchbackup --db "${db}" --log "${log_file}" >"${backup_file}"; then
            log_info "Successfully backed up '${db}'"
        else
            # Remove the empty backup file on failure
            rm -f "${backup_file}"
            die "Failed to back up '${db}'. Check log: '${log_file}'"
        fi
    done

    log_info "Local backup process complete."

    if [[ "${UPLOAD_TO_S3}" == "true" ]]; then
        upload_to_s3 "${backup_dir}"
    fi
}

# Uploads a directory to the configured S3 bucket.
upload_to_s3() {
    local dir_to_upload=$1
    local s3_path="s3://${S3_BUCKET}/${ENV}/$(basename "${dir_to_upload}")/"

    log_info "Uploading backup to S3 path: ${s3_path}"
    if ! aws s3 cp --endpoint-url "${S3_ENDPOINT_URL}" "${dir_to_upload}" "${s3_path}" --recursive; then
        die "S3 upload failed."
    fi
    log_info "S3 upload complete."
}

# Restores databases from a specified local backup directory.
restore_databases() {
    log_info "Starting restore process..."
    read -rp "Enter the full path to the backup directory to restore from: " backup_dir

    if [[ ! -d "${backup_dir}" ]]; then
        die "Directory not found: '${backup_dir}'"
    fi

    log_info "Restoring from: ${backup_dir}"

    for db in "${DATABASES[@]}"; do
        log_info "--- Restoring database: ${db} ---"
        local backup_file="${backup_dir}/${db}-backup.txt"

        if [[ ! -f "${backup_file}" ]]; then
            log_warn "Backup file not found for '${db}'. Skipping."
            continue
        fi

        log_info "Step 1: Ensuring database '${db}' exists..."
        # Use -I to check headers for the status code
        local http_status
        http_status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${COUCH_URL}/${db}")
        # 201 = Created, 412 = Precondition Failed (already exists)
        if [[ "${http_status}" -ne 201 && "${http_status}" -ne 412 ]]; then
            die "Failed to create database '${db}'. HTTP status: ${http_status}"
        fi

        log_info "Step 2: Restoring data from '${backup_file}'..."
        if cat "${backup_file}" | couchrestore --db "${db}"; then
            log_info "Successfully restored data to '${db}'."
        else
            die "Failed to restore data to '${db}'."
        fi
    done

    log_info "Restore process complete!"
}

# --- Main Execution Logic ---
usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

A script to backup and restore Cloudant databases.

Commands:
  backup    Perform a backup of the configured databases.
  restore   Interactively restore databases from a local backup directory.
  help      Show this help message.

Configuration (via environment variables):
  COUCH_URL           (Required) Full URL to Cloudant instance with credentials.
  DATABASES           (Optional) Space-separated list of databases.
                      Defaults to: "${DBS_TO_BACKUP}"
  ENV                 (Optional) Environment name (e.g., prod). Defaults to 'prod'.
  UPLOAD_TO_S3        (Optional) Set to 'true' to upload to S3. Defaults to 'false'.
  S3_BUCKET           (Optional) S3 bucket name for uploads.
  S3_ENDPOINT_URL     (Optional) S3 endpoint URL for non-AWS providers.
EOF
}

main() {
    # Default to 'help' if no command is provided.
    local command="${1:-backup}"

    case "${command}" in
        backup)
            check_dependencies
            install_couch_tools
            backup_databases
            ;;
        restore)
            check_dependencies
            install_couch_tools
            restore_databases
            ;;
        help | *)
            usage
            ;;
    esac
}

# --- NON-INTERACTIVE INPUT HANDLING (ADDED FOR CODE ENGINE) ---
if [[ "${1:-}" == "restore" ]]; then
    : "${BACKUP_DIR:?ERROR: BACKUP_DIR environment variable is not set.}"
    exec < <(echo "$BACKUP_DIR")
fi

main "$@"
