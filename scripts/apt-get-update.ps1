Write-Host "Updating installed packages"

bash -c "export DEBIAN_FRONTEND=noninteractive"
bash -c "apt-get update -y"
bash -c "apt-get upgrade -y"