#!/bin/bash

# Title: Deployment & SSH Key Rotation Script

set -euo pipefail

# --- Configuration Variables ---
ICR_API_KEY="<new-icr-api-key>"
ICR_SERVICE_ID="<new-icr-service-id>"
SECRETS_MANAGER_API_KEY="<secrets-manager-api-key>"
NEW_SSH_KEY_COMMENT="rotated-key-$(date +%Y%m%d)"
SSH_USER="workeruser"
WORKER_HOSTS=("worker1.example.com" "worker2.example.com") # Add more as needed
PRIVATE_KEY_PATH="/tmp/id_rsa_new"
PUBLIC_KEY_PATH="${PRIVATE_KEY_PATH}.pub"
AUDIT_LOG="/var/log/ssh_key_rotation.log"
SECRETS_MANAGER_VAULT_PATH="vault/path/to/store/key" # e.g., 1Password CLI or other tool path

# Frontend Deployment Updates (Code Engine) 

update_code_engine_apps() {
    echo "[INFO] Updating Code Engine deployments..."

    for app in listener gh-app; do
        echo "[INFO] Updating deployment for application: $app"

        ibmcloud ce application update \
            --name "$app" \
            --registry-api-key "$ICR_API_KEY" \
            --registry-secret "$ICR_SERVICE_ID" \
            --secrets-manager-api-key "$SECRETS_MANAGER_API_KEY"

        echo "[INFO] Deployment update triggered for $app"
    done
}

# Section 2: SSH Key Rotation Automation

rotate_ssh_keys() {
    echo "[INFO] Starting SSH key rotation..."

    # Generate new key pair
    ssh-keygen -t rsa -b 4096 -C "$NEW_SSH_KEY_COMMENT" -f "$PRIVATE_KEY_PATH" -N ""
    echo "[INFO] New SSH key pair generated."

    for host in "${WORKER_HOSTS[@]}"; do
        echo "[INFO] Installing new SSH key on $host..."

        # Copy new public key to authorized_keys
        ssh "$SSH_USER@$host" "mkdir -p ~/.ssh && echo \"$(cat $PUBLIC_KEY_PATH)\" >> ~/.ssh/authorized_keys"

        # Test new key access
        chmod 600 "$PRIVATE_KEY_PATH"
        if ssh -i "$PRIVATE_KEY_PATH" "$SSH_USER@$host" "echo [SUCCESS] Key works on $host"; then
            echo "[INFO] Key validated on $host"
        else
            echo "[ERROR] Failed to validate new SSH key on $host" >&2
            exit 1
        fi

        # Remove old public key (assuming it has a recognizable comment or pattern)
        ssh "$SSH_USER@$host" "sed -i '/old-key-comment-or-pattern/d' ~/.ssh/authorized_keys"
        echo "[INFO] Old SSH key removed from $host"
    done
}

# Store New Private Key Securely in 1Password

store_key_securely() {
    echo "[INFO] Storing new private key securely in 1Password..."

    # Check if OP CLI is installed
    if ! command -v op &> /dev/null; then
        echo "[ERROR] 1Password CLI 'op' not found. Install it from https://developer.1password.com/docs/cli/" >&2
        exit 1
    fi

    # Check if user is signed in
    if ! op account list | grep -q 'SIGNED IN'; then
        echo "[ERROR] 1Password CLI is not signed in. Run: eval \$(op signin)" >&2
        exit 1
    fi

    ITEM_TITLE="Frontend SSH Key $(date +%F)"
    VAULT_NAME="DevOps Vault"  # <-- Change this to your actual vault name

    # Create a secure note with key details
    op item create --vault "$VAULT_NAME" --title "$ITEM_TITLE" \
        --category "Secure Note" \
        "private_key[text]=$(<"$PRIVATE_KEY_PATH")" \
        "public_key[text]=$(<"$PUBLIC_KEY_PATH")" \
        "comment[text]=$NEW_SSH_KEY_COMMENT" \
        "rotation_date[text]=$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[INFO] SSH key securely stored in 1Password vault: $VAULT_NAME"
}


log_rotation_event() {
    echo "[INFO] Logging rotation event..."

    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH key rotated. New key: $NEW_SSH_KEY_COMMENT"
    } >> "$AUDIT_LOG"

    echo "[INFO] Rotation event logged."
}

# --- Main Execution Flow ---

main() {
    update_code_engine_apps
    rotate_ssh_keys
    store_key_securely
    log_rotation_event
    echo "[INFO] All tasks completed successfully."
}

main
