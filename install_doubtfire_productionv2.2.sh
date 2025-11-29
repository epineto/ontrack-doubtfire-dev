#!/usr/bin/env bash
set -e

echo "====================================================="
echo "   🚀 Doubtfire LMS – Automated PRODUCTION Installer v2.2"
echo "====================================================="

### ----------------------------------------------------
### 1. Install Docker Engine
### ----------------------------------------------------
echo "📦 Installing Docker Engine..."

apt-get update --fix-missing
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
 | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update --fix-missing
apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin

systemctl enable docker
systemctl start docker

echo "✔ Docker installed."


### ----------------------------------------------------
### 2. Install Docker Compose v2
### ----------------------------------------------------
echo "🔧 Installing Docker Compose v2..."

LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
  | grep browser_download_url \
  | grep 'docker-compose-linux-x86_64"' \
  | cut -d '"' -f 4)

mkdir -p /usr/local/libexec/docker/cli-plugins
curl -SL "$LATEST_COMPOSE" \
  -o /usr/local/libexec/docker/cli-plugins/docker-compose

chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose

ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

echo "✔ Docker Compose installed:"
docker compose version


### ----------------------------------------------------
### 3. Clone Doubtfire Deploy Repo
### ----------------------------------------------------
echo "📥 Cloning production repo..."

mkdir -p /home/$SUDO_USER/doubtfire
cd /home/$SUDO_USER/doubtfire

git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy

cd doubtfire-deploy
git submodule update --init --recursive

echo "✔ Repositories cloned."


### ----------------------------------------------------
### 4. Write production docker-compose.yml (NO proxy)
### ----------------------------------------------------
echo "📝 Writing production docker-compose.yml..."

cat > /home/$SUDO_USER/doubtfire/doubtfire-deploy/production/docker-compose.yml <<'EOF'
services:
  doubtfire-db:
    image: mariadb:10
    container_name: production-doubtfire-db-1
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: doubtfire
      MYSQL_USER: dfire
      MYSQL_PASSWORD: pwd
    volumes:
      - ../data/database:/var/lib/mysql
    ports:
      - "3306:3306"

  apiserver:
    image: lmsdoubtfire/apiserver:10.0.0-4
    container_name: production-apiserver-1
    restart: always
    depends_on:
      - doubtfire-db
    environment:
      RAILS_ENV: production
      DB_HOST: doubtfire-db
      DB_USERNAME: dfire
      DB_PASSWORD: pwd
      DB_DATABASE: doubtfire
      SECRET_KEY_BASE: "super-secret-key"
    ports:
      - "3000:3000"

  webserver:
    image: lmsdoubtfire/doubtfire-web:10.0.0-3
    container_name: production-webserver-1
    restart: always
    depends_on:
      - apiserver
    environment:
      API_URL: "http://localhost:3000"
    ports:
      - "8080:80"
EOF

echo "✔ production docker-compose.yml written."


### ----------------------------------------------------
### 5. Start Production Stack
### ----------------------------------------------------
echo "🚀 Starting Doubtfire PRODUCTION environment..."

cd /home/$SUDO_USER/doubtfire/doubtfire-deploy/production

docker compose down --remove-orphans
docker compose up -d --build

echo "====================================================="
echo "   🎉 Doubtfire PRODUCTION is now running!"
echo "   🌐 Web UI: http://localhost:8080"
echo "   🔌 API:    http://localhost:3000"
echo "   🗄  DB:     localhost:3306 (user=dfire pwd=pwd)"
echo "====================================================="
