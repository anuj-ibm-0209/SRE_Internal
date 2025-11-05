#!/bin/bash

# Description: Create or update a service ID and store its API key in 1Password
# Must be run by: actions-deploy

set -euo pipefail

# Configuration

EXPECTED_USER="actions-deploy"
OP_ITEM_TITLE="Monthly Release Service API"
OP_API_KEY_FIELD="API_KEY"
PERMISSIONS="read:repo, write:deployments, manage:secrets"

# Functions

log() {
  echo "[INFO] $1"
}

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

check_user() {
  [[ "$(whoami)" == "$EXPECTED_USER" ]] || error_exit "Script must be run as $EXPECTED_USER"
}

generate_api_key() {
  uuidgen
}

service_exists() {
  [[ -f "./${SERVICE_ID}.json" ]]
}

create_service() {
  log "Creating service ID '$SERVICE_ID'..."
  echo "{\"id\": \"$SERVICE_ID\", \"permissions\": \"$PERMISSIONS\"}" > "${SERVICE_ID}.json"
}

update_permissions() {
  log "Updating permissions for '$SERVICE_ID'..."
  echo "{\"id\": \"$SERVICE_ID\", \"permissions\": \"$PERMISSIONS\"}" > "${SERVICE_ID}.json"
}

update_1password() {
  log "Updating API key in 1Password..."
  op item edit "$OP_ITEM_TITLE" "$OP_API_KEY_FIELD=$NEW_API_KEY" || error_exit "Failed to update API key in 1Password"
}

# Check user

check_user

read -rp "Enter Service ID: " SERVICE_ID
[[ -z "$SERVICE_ID" ]] && error_exit "Service ID cannot be empty."

if service_exists; then
  log "Service ID '$SERVICE_ID' already exists."
  update_permissions
else
  create_service
fi

NEW_API_KEY=$(generate_api_key)
log "Generated API key: $NEW_API_KEY"

update_1password

log "Done. Service ID '$SERVICE_ID' is ready with updated API key."
