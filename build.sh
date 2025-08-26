#!/bin/bash

PACKAGES=($(find charts -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))
for PACKAGE in "${PACKAGES[@]}"; do
    echo "debug: Found package: $PACKAGE"
done
CURRENT_DIR=$(pwd)

for PACKAGE in "${PACKAGES[@]}"; do
    # Get version from Chart.yaml
    VERSION=$(grep '^version:' "charts/$PACKAGE/Chart.yaml" | awk '{print $2}')
    
    # Check if package tar already exists
    if [ ! -f "docs/$PACKAGE-$VERSION.tgz" ]; then
        cd "charts/$PACKAGE"
        helm dep up
        cd $CURRENT_DIR
        helm package "charts/$PACKAGE"
        mv "$PACKAGE-$VERSION.tgz" docs/
    else
        echo "Package $PACKAGE-$VERSION.tgz already exists, skipping..."
    fi
done

helm repo index --merge docs/index.yaml --url https://charts.motyka.pro .
mv index.yaml docs/
sed -i 's#/docs/#/#g' docs/index.yaml

# Create index.html in docs/ with links to all tgz files in docs/
cat > docs/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>artur9010 Chart Repository</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css">
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
</head>
<body>
<main class="container">
<h1>artur9010 Chart Repository</h1>
<p>To add this repository, run: <code>helm repo add artur9010 https://charts.motyka.pro</code></p>
<ul>
EOF

for PACKAGE in "${PACKAGES[@]}"; do
    echo "<li><a href=\"https://artifacthub.io/packages/helm/artur9010/$PACKAGE\" rel=\"noopener nofollow\" target=\"_blank\">See $PACKAGE on ArtifactHub</a></li>" >> docs/index.html
done

echo "</ul><h2>Downloads</h2><ul>" >> docs/index.html

for f in docs/*.tgz; do
  if [ -f "$f" ]; then
    filename=$(basename "$f")
    echo "  <li><a href=\"$filename\">$filename</a></li>" >> docs/index.html
  fi
done

cat >> docs/index.html <<EOF
</ul>
</main>
</body>
</html>
EOF

echo "Successfully generated docs/index.html"