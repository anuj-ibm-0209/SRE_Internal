#!/usr/bin/env python3

import os
import sys
import subprocess
import uuid
import json
from pathlib import Path

# Configuration

EXPECTED_USER = "actions-deploy"
OP_ITEM_TITLE = "Monthly Release Service API"
OP_API_KEY_FIELD = "API_KEY"
PERMISSIONS = ["read:repo", "write:deployments", "manage:secrets"]
DATA_DIR = Path(".")
SERVICE_FILE_EXTENSION = ".json"

# Logging Helpers

def log(msg):
    print(f"[INFO] {msg}")

def error_exit(msg):
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)

# Functional Helpers

def check_user():
    current_user = os.getlogin()
    if current_user != EXPECTED_USER:
        error_exit(f"This script must be run as '{EXPECTED_USER}', not '{current_user}'.")

def generate_api_key():
    return str(uuid.uuid4())

def get_service_file(service_id):
    return DATA_DIR / f"{service_id}{SERVICE_FILE_EXTENSION}"

def service_exists(service_id):
    return get_service_file(service_id).exists()

def create_or_update_service(service_id):
    log(f"Creating or updating service ID '{service_id}'...")
    service_data = {
        "id": service_id,
        "permissions": PERMISSIONS
    }
    with open(get_service_file(service_id), "w") as f:
        json.dump(service_data, f, indent=2)
    log(f"Service ID '{service_id}' saved.")

def update_1password(api_key):
    log("Updating API key in 1Password...")
    try:
        subprocess.run([
            "op", "item", "edit", OP_ITEM_TITLE, f"{OP_API_KEY_FIELD}={api_key}"
        ], check=True)
    except subprocess.CalledProcessError:
        error_exit("Failed to update API key in 1Password.")

# Finally, the main logic

def main():
    check_user()

    service_id = input("Enter Service ID: ").strip()
    if not service_id:
        error_exit("Service ID cannot be empty.")

    if service_exists(service_id):
        log(f"Service ID '{service_id}' already exists. Updating permissions...")
    else:
        log(f"Service ID '{service_id}' not found. Creating new...")

    create_or_update_service(service_id)

    new_api_key = generate_api_key()
    log(f"Generated new API key: {new_api_key}")
    update_1password(new_api_key)

    log(f"Done. Service ID '{service_id}' is ready with updated API key.")

if __name__ == "__main__":
    main()
