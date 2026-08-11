#!/bin/bash

set -e

IMAGE="zero-downtime-demo-app"
NETWORK="zero-downtime-demo_default"
NGINX_CONTAINER="demo-nginx"
NGINX_CONFIG="nginx/nginx.conf"

echo "======================================"
echo " Zero Downtime Deployment"
echo "======================================"

# 1. Build new Docker image
echo "[1/6] Building Docker image..."

docker build -t "$IMAGE:latest" .

# 2. Detect current and new version
CURRENT=$(grep -oE 'server demo-v[12]:5000' "$NGINX_CONFIG" | grep -oE 'demo-v[12]' || true)

if [ "$CURRENT" = "demo-v1" ]; then
    NEW="demo-v2"
else
    NEW="demo-v1"
fi

echo "Current version: $CURRENT"
echo "New version: $NEW"

# 3. Start new version
echo "[2/6] Starting $NEW..."

docker rm -f "$NEW" 2>/dev/null || true

docker run -d \
    --name "$NEW" \
    --network "$NETWORK" \
    -e VERSION="$NEW" \
    "$IMAGE:latest"

# 4. Health check
echo "[3/6] Checking health..."

HEALTHY=false

for i in {1..30}
do
    if docker exec "$NEW" python -c \
        "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" \
        >/dev/null 2>&1
    then
        HEALTHY=true
        echo "✅ New version is healthy!"
        break
    fi

    echo "Waiting for application... ($i/30)"
    sleep 2
done

# Rollback if health check fails
if [ "$HEALTHY" != "true" ]; then
    echo "❌ Health check failed."
    echo "Rolling back..."

    docker logs "$NEW"
    docker rm -f "$NEW" 2>/dev/null || true

    echo "Rollback completed."
    exit 1
fi

# 5. Switch Nginx traffic
echo "[4/6] Switching traffic to $NEW..."

# Backup current Nginx configuration
cp "$NGINX_CONFIG" "$NGINX_CONFIG.backup"

# Change old version to new version
sed -i "s/server $CURRENT:5000;/server $NEW:5000;/" "$NGINX_CONFIG"

# Test Nginx configuration
if docker exec "$NGINX_CONTAINER" nginx -t; then

    # IMPORTANT:
    # nginx.conf is mounted from the host,
    # so we DO NOT use docker cp.

    docker exec "$NGINX_CONTAINER" nginx -s reload

    echo "✅ Traffic switched to $NEW."

else

    echo "❌ Nginx configuration failed."
    echo "Rolling back..."

    cp "$NGINX_CONFIG.backup" "$NGINX_CONFIG"

    docker exec "$NGINX_CONTAINER" nginx -s reload

    docker rm -f "$NEW" 2>/dev/null || true

    echo "Rollback completed."
    exit 1
fi

# 6. Test application through Nginx
echo "[5/6] Testing application..."

sleep 2

if curl -f http://localhost:8080/ >/dev/null 2>&1; then

    echo "✅ Application is responding."

else

    echo "❌ Application test failed."
    echo "Rolling back..."

    cp "$NGINX_CONFIG.backup" "$NGINX_CONFIG"

    docker exec "$NGINX_CONTAINER" nginx -s reload

    docker rm -f "$NEW" 2>/dev/null || true

    echo "Rollback completed."
    exit 1
fi

# 7. Remove old container
echo "[6/6] Cleaning up old version..."

docker rm -f "$CURRENT" 2>/dev/null || true

rm -f "$NGINX_CONFIG.backup"

echo ""
echo "======================================"
echo "✅ Deployment successful!"
echo "Live version: $NEW"
echo "======================================"