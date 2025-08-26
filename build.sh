#!/bin/bash

PACKAGES=("cloudflared" "renterd")

for PACKAGE in "${PACKAGES[@]}"; do
    # Get version from Chart.yaml
    VERSION=$(grep '^version:' "$PACKAGE/Chart.yaml" | awk '{print $2}')
    
    # Check if package tar already exists
    if [ ! -f "$PACKAGE-$VERSION.tgz" ]; then
        cd "$PACKAGE"
        helm dep up
        cd ..
        helm package "$PACKAGE"
    else
        echo "Package $PACKAGE-$VERSION.tgz already exists, skipping..."
    fi
done

helm repo index .