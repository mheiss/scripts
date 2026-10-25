Write-Host "Updating installed packages"

bash -c "export LC_ALL=C DEBIAN_FRONTEND=noninteractive && apt-get update -y"
if ($LASTEXITCODE -ne 0) {
	throw "apt-get update failed with exit code $LASTEXITCODE."
}
bash -c "export LC_ALL=C DEBIAN_FRONTEND=noninteractive && apt-get upgrade -y"
if ($LASTEXITCODE -ne 0) {
	throw "apt-get upgrade failed with exit code $LASTEXITCODE."
}