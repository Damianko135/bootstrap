#!/usr/bin/env bash
# Linux/Unix Bootstrap
# Simple entry point for Linux-only bootstrapping
# Usage: bash bootstrap.sh --profile standard

set -e

# Configuration
RAW_URL="https://raw.githubusercontent.com/Damianko135/bootstrap/main"

# Default values
PROFILE="standard"
SKIP_PACKAGES=false
SKIP_PROFILE=false
FORCE=false
LOCAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --skip-packages)
            SKIP_PACKAGES=true
            shift
            ;;
        --skip-profile)
            SKIP_PROFILE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --local)
            LOCAL=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$LOCAL" = true ]; then
    bash linux/init.sh --profile "$PROFILE" \
        $([ "$SKIP_PACKAGES" = true ] && echo "--skip-packages") \
        $([ "$SKIP_PROFILE" = true ] && echo "--skip-profile") \
        $([ "$FORCE" = true ] && echo "--force")
else
    bash <(curl -sSL "$RAW_URL/linux/init.sh") --profile "$PROFILE" \
        $([ "$SKIP_PACKAGES" = true ] && echo "--skip-packages") \
        $([ "$SKIP_PROFILE" = true ] && echo "--skip-profile") \
        $([ "$FORCE" = true ] && echo "--force")
fi
