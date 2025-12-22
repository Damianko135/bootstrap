#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Linux Laptop Automation Setup Script
# Author: Damian Korver
# Description: Automates Linux laptop setup via Ansible playbook.
# Usage: Run with root privileges.
# ---------------------------------------------------------------------------

set -euo pipefail  # Strict error handling

# Ensure running as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script must be run as root. Use sudo or switch to root."
    exit 1
fi

# Check for python3
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Please install Python 3.8 or newer."
    exit 1
fi

# Check for python3-venv availability (to avoid venv module missing error)
if ! python3 -m venv --help &>/dev/null; then
    echo "ERROR: python3-venv module not found. Install it (e.g. sudo apt install python3-venv) and rerun."
    exit 1
fi

# Setup absolute path for the virtual environment dir
VENV_DIR="$(pwd)/venv"

# Create virtual environment if not exists
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating virtual environment at $VENV_DIR ..."
    python3 -m venv "$VENV_DIR"
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Upgrade pip inside venv
echo "Upgrading pip inside virtual environment..."
pip install --upgrade pip

# Check if requirements.txt exists
if [[ ! -f requirements.txt ]]; then
    echo "ERROR: requirements.txt file not found in current directory."
    deactivate
    exit 1
fi

# Install required Python packages
echo "Installing Ansible and dependencies from requirements.txt..."
pip install -r requirements.txt

# Run Ansible playbook with privilege escalation password prompt
if [[ ! -f playbook.yml ]]; then
    echo "ERROR: playbook.yml file not found in current directory."
    deactivate
    exit 1
fi

echo "Running Ansible playbook..."
ansible-playbook playbook.yml --ask-become-pass

# Deactivate virtual environment
deactivate

echo "Setup completed successfully."
