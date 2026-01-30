echo "Update installed packages"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y