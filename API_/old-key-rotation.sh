#!/bin/bash

# Configuration
WORKER_MACHINES=("worker1.example.com" "worker2.example.com")
OLD_KEY_COMMENT="old-key-comment"   # Used to identify old key in authorized_keys
NEW_KEY_COMMENT="rotated-key-$(date +%Y%m%d)"
PRIVATE_KEY_PATH="./id_rsa_rotated"
PUBLIC_KEY_PATH="${PRIVATE_KEY_PATH}.pub"
LOG_FILE="./ssh_key_rotation.log"
OP_VAULT="SSH Keys"
OP_ITEM_TITLE="Worker SSH Key"

# Generate a new SSH key pair
echo "[*] Generating new SSH key pair..."
ssh-keygen -t rsa -b 4096 -f "$PRIVATE_KEY_PATH" -C "$NEW_KEY_COMMENT" -N "" || exit 1

# Distribute public key to all worker machines
echo "[*] Distributing new public key to worker machines..."
for HOST in "${WORKER_MACHINES[@]}"; do
    echo "    -> Installing key on $HOST"
    ssh-copy-id -i "$PUBLIC_KEY_PATH" "$USER@$HOST" || { echo "Failed to copy key to $HOST"; exit 1; }
done

# Validate new key provides access
echo "[*] Validating access with new key..."
for HOST in "${WORKER_MACHINES[@]}"; do
    ssh -i "$PRIVATE_KEY_PATH" -o BatchMode=yes "$USER@$HOST" "echo Access to $HOST validated" || { echo "Validation failed for $HOST"; exit 1; }
done

# Remove old public key from worker machines
echo "[*] Removing old public key from worker machines..."
for HOST in "${WORKER_MACHINES[@]}"; do
    echo "    -> Cleaning up old key on $HOST"
    ssh -i "$PRIVATE_KEY_PATH" "$USER@$HOST" "sed -i '/$OLD_KEY_COMMENT/d' ~/.ssh/authorized_keys" || { echo "Failed to remove old key from $HOST"; exit 1; }
done

# Store new private key securely (1Password CLI)
echo "[*] Storing new private key in 1Password..."
if command -v op &> /dev/null; then
    op item create --vault "$OP_VAULT" --category "SSH Key" --title "$OP_ITEM_TITLE" \
        "private key[password]=$(< $PRIVATE_KEY_PATH)" \
        "public key[text]=$(< $PUBLIC_KEY_PATH)" \
        "comment[text]=$NEW_KEY_COMMENT" \
        || { echo "Failed to store SSH key in 1Password"; exit 1; }
else
    echo "1Password CLI not found. Please install it or store the key manually."
    exit 1
fi

# Log rotation event
echo "[*] Logging key rotation..."
{
    echo "[$(date)] SSH key rotated."
    echo "  New comment: $NEW_KEY_COMMENT"
    echo "  Machines: ${WORKER_MACHINES[*]}"
} >> "$LOG_FILE"

# Done
echo "[✓] SSH key rotation complete."
