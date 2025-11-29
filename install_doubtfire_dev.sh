#!/usr/bin/env bash
set -e

echo "====================================================="
echo " 🚀 OnTrack / Doubtfire – FULL DEV ENV Installer"
echo "====================================================="

# Detect normal user
NORMAL_USER=${SUDO_USER:-$USER}
HOME_DIR=$(eval echo "~$NORMAL_USER")

echo "👤 Running setup for user: $NORMAL_USER"
sleep 1

### ----------------------------------------------------
### 1. Install required packages
### ----------------------------------------------------
echo "📦 Installing base dependencies..."
sudo apt-get update -y
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common

### ----------------------------------------------------
### 2. Install Docker Desktop
### ----------------------------------------------------
echo "🐳 Installing Docker Desktop..."

curl -L "https://desktop.docker.com/linux/main/amd64/docker-desktop.deb" \
  -o docker-desktop.deb

sudo apt-get install -y ./docker-desktop.deb
rm docker-desktop.deb

sudo systemctl enable docker-desktop
sudo systemctl start docker-desktop

echo "✔ Docker Desktop installed."
sleep 1

### ----------------------------------------------------
### 3. Install VS Code
### ----------------------------------------------------
echo "🧩 Installing Visual Studio Code..."

wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/keyrings/
rm microsoft.gpg

sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'

sudo apt-get update -y
sudo apt-get install -y code

echo "✔ VS Code installed."

### ----------------------------------------------------
### 4. Install VS Code Dev Containers extension
### ----------------------------------------------------
echo "📦 Installing VS Code Dev Container extension..."

sudo -u $NORMAL_USER code --install-extension ms-vscode-remote.remote-containers || true

echo "✔ Dev Containers extension installed."

### ----------------------------------------------------
### 5. Pull official OnTrack dev container image
### ----------------------------------------------------
echo "🐳 Pulling official dev container image..."

sudo docker pull lmsdoubtfire/formatif-dev-container:10.0.0-14

echo "✔ Dev container image pulled."

### ----------------------------------------------------
### 6. Clone repositories
### ----------------------------------------------------
echo "📥 Cloning repositories into $HOME_DIR/ontrack..."

mkdir -p $HOME_DIR/ontrack
cd $HOME_DIR/ontrack

sudo -u $NORMAL_USER git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-deploy
sudo -u $NORMAL_USER git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-api
sudo -u $NORMAL_USER git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-web
sudo -u $NORMAL_USER git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-lti

echo "✔ All repositories cloned."

### ----------------------------------------------------
### 7. Initialise submodules
### ----------------------------------------------------
echo "🔧 Initialising git submodules..."

cd doubtfire-deploy
sudo -u $NORMAL_USER git submodule update --init --recursive

echo "✔ Submodules ready."

### ----------------------------------------------------
### 8. Open VS Code & auto-trigger container
### ----------------------------------------------------
echo "🧑‍💻 Opening VS Code in dev environment..."

sudo -u $NORMAL_USER code $HOME_DIR/ontrack/doubtfire-deploy

sleep 2

echo "====================================================="
echo " 🎉 Setup complete!"
echo " 👉 In VS Code, click: 'Reopen in Container'"
echo " ====================================================="
echo "Once inside the container:"
echo "  ▶ API:   rails s"
echo "  ▶ WEB:   npm run start-compose"
echo "====================================================="
