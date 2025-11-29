#!/usr/bin/env bash
set -e

echo "====================================================="
echo "   🚀 Doubtfire LMS – Production Installer v2.1"
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
### 2. Install Docker Compose v2 (fixed URL detection)
### ----------------------------------------------------
echo "🔧 Installing Docker Compose v2..."

ARCH=$(uname -m)
case $ARCH in
    x86_64) COMPOSE_ARCH="x86_64" ;;
    aarch64|arm64) COMPOSE_ARCH="aarch64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
  | grep "docker-compose-linux-$COMPOSE_ARCH\"" \
  | cut -d '"' -f 4 | head -n 1)

if [[ -z "$LATEST_COMPOSE" ]]; then
    echo "❌ ERROR: Could not retrieve Docker Compose binary URL."
    exit 1
fi

mkdir -p /usr/local/libexec/docker/cli-plugins

curl -L "$LATEST_COMPOSE" \
  -o /usr/local/libexec/docker/cli-plugins/docker-compose

chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose

ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

echo "✔ Docker Compose installed:"
docker compose version


### ----------------------------------------------------
### 3. Clone Doubtfire Deploy – Production Branch
### ----------------------------------------------------
echo "📥 Cloning doubtfire-deploy (production)..."

mkdir -p /home/$SUDO_USER/doubtfire
cd /home/$SUDO_USER/doubtfire

if [[ -d "doubtfire-deploy" ]]; then
  echo "⚠ Existing doubtfire-deploy directory found. Skipping clone."
else
  git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy
fi

cd doubtfire-deploy
git submodule update --init --recursive

echo "✔ Repositories cloned."


### ----------------------------------------------------
### 4. Create production docker-compose.yml
### ----------------------------------------------------
echo "📝 Writing production docker-compose.yml..."

cat > production/docker-compose.yml <<'EOF'
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
    # Uncomment to access DB externally:
    # ports:
    #   - "3306:3306"

  apiserver:
    image: lmsdoubtfire/apiserver:10.0.0-4
    container_name: production-apiserver-1
    restart: always
    environment:
      RAILS_ENV: production
      DB_HOST: doubtfire-db
      DB_USERNAME: dfire
      DB_PASSWORD: pwd
      DB_DATABASE: doubtfire
    depends_on:
      - doubtfire-db
    ports:
      - "3000:3000"

  webserver:
    image: lmsdoubtfire/doubtfire-web:10.0.0-3
    container_name: production-webserver-1
    restart: always
    depends_on:
      - apiserver
    ports:
      - "8080:8080"

volumes:
  database:
EOF

echo "✔ docker-compose.yml updated."


### ----------------------------------------------------
### 5. Start Production Environment
### ----------------------------------------------------
echo "🚀 Starting Doubtfire PRODUCTION environment..."

cd production
docker compose down --remove-orphans || true
docker compose pull
docker compose up -d --build

echo "====================================================="
echo "🎉 Doubtfire PRODUCTION is now running!"
echo " "
echo "   🌐 Web Interface:  http://localhost:8080"
echo "   🔌 API Server:     http://localhost:3000"
echo "   🗄  Database:       Internal only (enable ports to expose)"
echo " "
echo "====================================================="
