Write-Host "Updating installed packages"

bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -y"
bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get upgrade -y"