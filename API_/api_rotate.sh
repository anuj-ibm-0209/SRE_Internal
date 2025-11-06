#!/bin/bash
# Title: IBM Cloud Service ID Management Script
# Prerequisites
# 1. IBM Cloud CLI installed and authenticated (https://cloud.ibm.com/docs/cli)
# 2. 1Password CLI installed and signed in (https://developer.1password.com/docs/cli)
# 3. Environment variables:
#    - IBM_CLOUD_FUNCTIONAL_ID_EMAIL
#    - IBM_CLOUD_FUNCTIONAL_ID_API_KEY
#    - SERVICE_ID_NAME
#    - 1PASSWORD_VAULT
#    - 1PASSWORD_ITEM_NAME

set -euo pipefail

# Load environment variables from .env file

if [ -f ".env" ]; then
    set -a
    source .env
    set +a
else
    echo "No .env file found."
    exit 1
fi

# Validate required variables

REQUIRED_VARS=(
  IBM_CLOUD_FUNCTIONAL_ID_API_KEY
  SERVICE_ID_NAME
  1PASSWORD_VAULT
  1PASSWORD_ITEM_NAME
)

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR:-}" ]; then
    echo "ERROR: Required environment variable '$VAR' is not set."
    echo "Please define it in your .env file or export it before running the script."
    exit 1
  fi
done
# Configuration

SERVICE_ID_NAME="${SERVICE_ID_NAME:-monthly-release-service-id}"
VAULT="${_1PASSWORD_VAULT:-MonthlyReleases}"
ITEM_NAME="${_1PASSWORD_ITEM_NAME:-IBM Cloud API Key}"
ROLE="Writer"  # Adjust as per monthly release permissions
RESOURCE_GROUP="Default"  # Adjust if needed

LOG_FILE="./service_id_management.log"

echo "===== $(date) - Starting Service ID management =====" | tee -a "$LOG_FILE"


# Login to IBM Cloud

echo "Logging in to IBM Cloud..." | tee -a "$LOG_FILE"

ibmcloud login --apikey "$IBM_CLOUD_FUNCTIONAL_ID_API_KEY" -r us-south 1>>"$LOG_FILE" 2>&1 || {
    echo "ERROR: IBM Cloud login failed." | tee -a "$LOG_FILE"
    exit 1
}

# Check if Service ID exists

EXISTING_SERVICE_ID=$(ibmcloud iam service-id $SERVICE_ID_NAME --output json | jq -r '.id' 2>/dev/null || echo "")

if [ -z "$EXISTING_SERVICE_ID" ] || [ "$EXISTING_SERVICE_ID" == "null" ]; then
    echo "Service ID does not exist. Creating a new one..." | tee -a "$LOG_FILE"
    SERVICE_ID_JSON=$(ibmcloud iam service-id-create "$SERVICE_ID_NAME" -d "Service ID for monthly releases" --output json)
    SERVICE_ID=$(echo "$SERVICE_ID_JSON" | jq -r '.id')
else
    echo "Service ID exists: $EXISTING_SERVICE_ID" | tee -a "$LOG_FILE"
    SERVICE_ID="$EXISTING_SERVICE_ID"
fi

# Create or update API key

echo "Generating/updating API key..." | tee -a "$LOG_FILE"

# Delete old API keys
OLD_KEYS=$(ibmcloud iam service-api-keys --service-id "$SERVICE_ID" --output json | jq -r '.[].name')
for key in $OLD_KEYS; do
    echo "Deleting old API key: $key" | tee -a "$LOG_FILE"
    ibmcloud iam service-api-key-delete "$key" -f 1>>"$LOG_FILE" 2>&1
done

# Create new API key
API_KEY_JSON=$(ibmcloud iam service-api-key-create "$SERVICE_ID_NAME-key" --service-id "$SERVICE_ID" -d "Monthly release key" --output json)
API_KEY=$(echo "$API_KEY_JSON" | jq -r '.apikey')

if [ -z "$API_KEY" ] || [ "$API_KEY" == "null" ]; then
    echo "ERROR: Failed to create API key." | tee -a "$LOG_FILE"
    exit 1
fi

# Assign required roles

echo "Assigning roles..." | tee -a "$LOG_FILE"

# assign 'Writer' role to the default resource group
ibmcloud iam service-id-policy-create "$SERVICE_ID" --roles "$ROLE" --resource-group-name "$RESOURCE_GROUP" 1>>"$LOG_FILE" 2>&1 || {
    echo "ERROR: Failed to assign role $ROLE." | tee -a "$LOG_FILE"
    exit 1
}

# Update API key in 1Password

echo "Updating API key in 1Password vault '$VAULT', item '$ITEM_NAME'..." | tee -a "$LOG_FILE"

op item edit "$ITEM_NAME" "notesPlain=$API_KEY" --vault "$VAULT" 1>>"$LOG_FILE" 2>&1 || {
    echo "ERROR: Failed to update 1Password item." | tee -a "$LOG_FILE"
    exit 1
}

echo "Service ID management completed successfully." | tee -a "$LOG_FILE"
echo "Service ID: $SERVICE_ID"
echo "API key updated in 1Password item '$ITEM_NAME' in vault '$VAULT'"

