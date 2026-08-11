#!/bin/bash

set -e

IMAGE="zero-downtime-demo-app"
NETWORK="zero-downtime-demo_default"
NGINX_CONFIG="nginx/nginx.conf"
NGINX_CONTAINER="demo-nginx"

echo "======================================"
echo " Zero Downtime Deployment"
echo "======================================"

# 1. Build image

echo "[1/6] Building Docker image..."

docker build -t "$IMAGE:latest" .

# 2. Detect current version

CURRENT=$(grep -oE 'server demo-v[12]:5000;' "$NGINX_CONFIG" | head -1 | grep -oE 'demo-v[12]')

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

docker run -d 
--name "$NEW" 
--network "$NETWORK" 
-e VERSION="$NEW" 
"$IMAGE:latest"

# 4. Health check

echo "[3/6] Checking health..."

HEALTHY=false

for i in {1..30}
do
if docker exec "$NEW" python -c 
"import urllib.request; urllib.request.urlopen('http://localhost:5000/health', timeout=5)" 
>/dev/null 2>&1
then
HEALTHY=true
echo "New version is healthy!"
break
fi

```
echo "Waiting for application... ($i/30)"
sleep 2
```

done

if [ "$HEALTHY" != "true" ]; then
echo "Health check failed."
echo "Rolling back..."

```
docker logs "$NEW" || true
docker rm -f "$NEW" 2>/dev/null || true

echo "Rollback completed."
exit 1
```

fi

# 5. Switch Nginx traffic

echo "[4/6] Switching traffic to $NEW..."

cp "$NGINX_CONFIG" "$NGINX_CONFIG.backup"

sed -i "s/server $CURRENT:5000;/server $NEW:5000;/" "$NGINX_CONFIG"

echo "Testing Nginx configuration..."

if docker exec "$NGINX_CONTAINER" nginx -t
then
docker exec "$NGINX_CONTAINER" nginx -s reload

```
echo "Traffic switched to $NEW."
```

else
echo "Nginx configuration failed."
echo "Rolling back..."

```
cp "$NGINX_CONFIG.backup" "$NGINX_CONFIG"

docker exec "$NGINX_CONTAINER" nginx -s reload || true

docker rm -f "$NEW" 2>/dev/null || true

echo "Rollback completed."
exit 1
```

fi

# 6. Verify traffic through Nginx

echo "[5/6] Testing application through Nginx..."

sleep 2

if docker run --rm 
--network "$NETWORK" 
python:3.12-slim 
python -c 
"import urllib.request; r=urllib.request.urlopen('http://demo-nginx/', timeout=5); print(r.read().decode()); exit(0 if r.status == 200 else 1)"
then
echo "Application is responding through Nginx."
else
echo "Application test failed."
echo "Rolling back..."

```
cp "$NGINX_CONFIG.backup" "$NGINX_CONFIG"

docker exec "$NGINX_CONTAINER" nginx -s reload || true

docker rm -f "$NEW" 2>/dev/null || true

echo "Rollback completed."
exit 1
```

fi

# Remove old version

echo "[6/6] Cleaning up old version..."

docker rm -f "$CURRENT" 2>/dev/null || true

rm -f "$NGINX_CONFIG.backup"

echo ""
echo "======================================"
echo " Deployment successful!"
echo " Live version: $NEW"
echo "======================================"
