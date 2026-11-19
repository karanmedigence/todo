Write-Host "Updating MongoDB Atlas IP..."

atlas accessLists create --currentIp

if ($LASTEXITCODE -eq 0) {
    Write-Host "Atlas IP updated successfully!"
} else {
    Write-Host "Atlas IP update failed!"
    exit 1
}