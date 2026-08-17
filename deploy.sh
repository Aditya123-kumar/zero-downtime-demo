#!/bin/bash

set -e

IMAGE="zero-downtime-demo-app:latest"
NETWORK="zero-downtime-demo_default"
NGINX_CONFIG="nginx/nginx.conf"
NGINX_CONTAINER="demo-nginx"

echo "======================================"
echo " Zero Downtime Deployment"
echo "======================================"

echo "[1/6] Detecting current version..."

if grep -q "server demo-v1:5000;" "$NGINX_CONFIG"; then
    CURRENT="demo-v1"
    NEW="demo-v2"
else
    CURRENT="demo-v2"
    NEW="demo-v1"
fi

echo "Current version: $CURRENT"
echo "New version: $NEW"

echo "[2/6] Starting $NEW..."

sudo docker rm -f "$NEW" 2>/dev/null || true

sudo docker run -d \
    --name "$NEW" \
    --network "$NETWORK" \
    -e VERSION="$NEW" \
    "$IMAGE"

echo "New container started."

echo "[3/6] Health checking $NEW..."

HEALTHY=false

for i in {1..30}
do
    if sudo docker exec "$NEW" python -c \
        "import urllib.request; urllib.request.urlopen('http://localhost:5000/health', timeout=5)" \
        >/dev/null 2>&1
    then
        HEALTHY=true
        echo "New version is healthy!"
        break
    fi

    echo "Waiting for application... ($i/30)"
    sleep 2
done

if [ "$HEALTHY" != "true" ]; then

    echo "Health check failed."
    echo "Rolling back..."

    sudo docker logs "$NEW" || true
    sudo docker rm -f "$NEW" 2>/dev/null || true

    echo "Rollback completed."
    exit 1
fi

echo "[4/6] Switching traffic to $NEW..."

cp "$NGINX_CONFIG" "$NGINX_CONFIG.backup"

sed -i "s/server $CURRENT:5000;/server $NEW:5000;/" "$NGINX_CONFIG"

echo "Testing Nginx configuration..."

if sudo docker exec "$NGINX_CONTAINER" nginx -t
then

    sudo docker exec "$NGINX_CONTAINER" nginx -s reload

    echo "Traffic switched to $NEW."

else

    echo "Nginx configuration failed."
    echo "Rolling back..."

    cp "$NGINX_CONFIG.backup" "$NGINX_CONFIG"

    sudo docker exec "$NGINX_CONTAINER" nginx -s reload || true
    sudo docker rm -f "$NEW" 2>/dev/null || true

    echo "Rollback completed."
    exit 1
fi

echo "[5/6] Testing application through Nginx..."

sleep 2

if sudo docker run --rm \
    --network "$NETWORK" \
    python:3.12-slim \
    python -c \
    "import urllib.request; r=urllib.request.urlopen('http://$NGINX_CONTAINER/', timeout=5); print(r.read().decode()); exit(0 if r.status == 200 else 1)"
then

    echo "Application is responding through Nginx."

else

    echo "Application test failed."
    echo "Rolling back..."

    cp "$NGINX_CONFIG.backup" "$NGINX_CONFIG"

    sudo docker exec "$NGINX_CONTAINER" nginx -s reload || true
    sudo docker rm -f "$NEW" 2>/dev/null || true

    echo "Rollback completed."
    exit 1
fi

echo "[6/6] Removing old version..."

sudo docker rm -f "$CURRENT" 2>/dev/null || true

rm -f "$NGINX_CONFIG.backup"

echo ""
echo "======================================"
echo " Deployment successful!"
echo " Live version: $NEW"
echo "======================================"
