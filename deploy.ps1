Write-Host "Health checking $newVersion..."

$healthy = $false

for ($i = 1; $i -le 12; $i++) {

    Write-Host "Health check attempt $i/12..."

    try {
        $health = docker exec $nginxContainer wget -qO- "http://${newVersion}:5000/health" 2>$null

        if ($LASTEXITCODE -eq 0 -and $health -match '"status"\s*:\s*"healthy"') {
            Write-Host "Health check passed!"
            Write-Host "Response: $health"
            $healthy = $true
            break
        }
    }
    catch {
        # Ignore and retry
    }

    Write-Host "Health check failed. Retrying..."
    Start-Sleep -Seconds 5
}

if (-not $healthy) {
    Write-Host "Health check failed after 12 attempts."
    Write-Host "Container logs:"
    docker logs $newVersion

    docker rm -f $newVersion 2>$null

    throw "New version failed health check."
}
