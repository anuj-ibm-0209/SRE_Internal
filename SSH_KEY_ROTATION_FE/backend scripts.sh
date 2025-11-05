#!/bin/bash

# Title: Backend Worker Deployment Update & SSH Key Rotation

set -euo pipefail

# Configuration Variables
SECRETS_MANAGER_API_KEY="<new-secrets-manager-api-key>"
GH_APP_URL="https://your-org.com/gh-app" # Replace with actual URL

SSH_USER="workeruser"
WORKER_HOSTS=("worker1.example.com" "worker2.example.com") # Add more as needed

LXD_CONTAINER_NAME="lxd-app"
RUNNER_BINARY_URL="https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz"

NEW_SSH_KEY_COMMENT="rotated-key-$(date +%Y%m%d)"
PRIVATE_KEY_PATH="/tmp/id_rsa_new"
PUBLIC_KEY_PATH="${PRIVATE_KEY_PATH}.pub"
AUDIT_LOG="/var/log/backend_ssh_key_rotation.log"
#SECRETS_MANAGER_VAULT_PATH="vault/path/to/backend/ssh-key" # Adjust as needed

# Update LXD Pod Config on Workers 

update_worker_config() {
    echo "[INFO] Updating Secrets Manager API key and gh-app URL on all workers..."

    for host in "${WORKER_HOSTS[@]}"; do
        echo "[INFO] Connecting to $host..."

        ssh "$SSH_USER@$host" bash <<EOF
echo "[INFO] Updating environment variables in LXD container $LXD_CONTAINER_NAME..."
lxc exec "$LXD_CONTAINER_NAME" -- bash -c '
    export SECRETS_MANAGER_API_KEY="$SECRETS_MANAGER_API_KEY"
    #export GH_APP_URL="$GH_APP_URL"
    echo "Secrets Manager API key and gh-app URL updated in environment."
'
EOF
    done
}

# Step 3: SSH Key Rotation

rotate_ssh_keys() {
    echo "[INFO] Rotating SSH keys..."

    # Generate new SSH key pair
    ssh-keygen -t rsa -b 4096 -C "$NEW_SSH_KEY_COMMENT" -f "$PRIVATE_KEY_PATH" -N ""
    echo "[INFO] New SSH key pair generated."

    for host in "${WORKER_HOSTS[@]}"; do
        echo "[INFO] Installing new SSH key on $host..."

        # Add new public key
        ssh "$SSH_USER@$host" "mkdir -p ~/.ssh && echo \"$(cat $PUBLIC_KEY_PATH)\" >> ~/.ssh/authorized_keys"

        # Validate access with new key
        chmod 600 "$PRIVATE_KEY_PATH"
        if ssh -i "$PRIVATE_KEY_PATH" "$SSH_USER@$host" "echo [SUCCESS] Verified key on $host"; then
            echo "[INFO] New key works on $host"
        else
            echo "[ERROR] SSH access validation failed for $host" >&2
            exit 1
        fi

        # Remove old key — customize the grep pattern as per your old key comment or fingerprint
        ssh "$SSH_USER@$host" "sed -i '/old-key-comment-or-pattern/d' ~/.ssh/authorized_keys"
        echo "[INFO] Old key removed from $host"
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

    ITEM_TITLE="Backend SSH Key $(date +%F)"
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


# Log Rotation Event

log_rotation_event() {
    echo "[INFO] Logging SSH key rotation..."

    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH key rotated for backend workers. New key: $NEW_SSH_KEY_COMMENT"
    } >> "$AUDIT_LOG"

    echo "[INFO] Event logged."
}

# Main Flow

main() {
    update_worker_config
    #upgrade_lxd_images
    rotate_ssh_keys
    store_key_securely
    log_rotation_event
    echo "[INFO] Backend worker update and SSH key rotation complete."
}

main
