#!/usr/bin/env bash
set -e

echo "====================================================="
echo "   🚀 Doubtfire LMS – Automated DEV Installer"
echo "====================================================="

### ----------------------------------------------------
### 0. Safety checks
### ----------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  echo "🛑 Please run as root: sudo ./install_doubtfire_dev.sh"
  exit 1
fi

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
### 2. Install Docker Compose v2 (Latest Official)
### ----------------------------------------------------
echo "🔧 Installing Docker Compose v2..."

mkdir -p /usr/local/libexec/docker/cli-plugins

LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
  | grep browser_download_url \
  | grep 'docker-compose-linux-x86_64"' \
  | cut -d '"' -f 4)

curl -L "$LATEST_COMPOSE" \
  -o /usr/local/libexec/docker/cli-plugins/docker-compose

chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose

# Remove any old versions
rm -f /usr/bin/docker-compose
rm -f /usr/local/bin/docker-compose

# fallback symlink
ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

echo "✔ Docker Compose v2 installed:"
docker compose version

### ----------------------------------------------------
### 3. Clone Doubtfire Deploy
### ----------------------------------------------------
echo "📥 Cloning doubtfire-deploy repo (dev)..."

mkdir -p /home/$SUDO_USER/doubtfire
cd /home/$SUDO_USER/doubtfire

git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy

cd doubtfire-deploy
git submodule update --init --recursive

echo "✔ Repositories cloned."

### ----------------------------------------------------
### 4. PATCH Dockerfiles (fix apt-get corruption + mirrors)
### ----------------------------------------------------
echo "🔧 Applying Dockerfile reliability patches..."

for file in $(find . -name Dockerfile); do
  echo "Patching: $file"

  sed -i 's/apt-get update/apt-get update --fix-missing/g' "$file"

  sed -i 's/apt-get install -y/apt-get install -y --fix-missing/g' "$file"

done

echo "✔ All Dockerfiles patched."

### ----------------------------------------------------
### 5. Write improved docker-compose.yml
### ----------------------------------------------------
echo "📝 Updating docker-compose.yml..."

cat > /home/$SUDO_USER/doubtfire/doubt­­fire-deploy/development/docker-compose.yml <<'EOF'
services:
  dev-db:
    image: mariadb
    container_name: df-compose-dev-db
    environment:
      MYSQL_ROOT_PASSWORD: db-root-password
      MYSQL_DATABASE: doubtfire-dev
      MYSQL_USER: dfire
      MYSQL_PASSWORD: pwd
    volumes:
      - ../data/database:/var/lib/mysql
    ports:
      - "3306:3306"

  redis-sidekiq:
    image: redis:7.0
    container_name: df-compose-redis-sidekiq
    volumes:
      - redis_sidekiq_data:/data
    ports:
      - "6379:6379"

  doubtfire-api:
    container_name: doubtfire-api
    build: ../doubtfire-api
    image: lmsdoubtfire/doubtfire-api:10.0.x-dev
    ports:
      - "3000:3000"
    depends_on:
      - dev-db
      - redis-sidekiq
    environment:
      RAILS_ENV: development
      DF_DEV_DB_HOST: df-compose-dev-db
      DF_DEV_DB_USERNAME: dfire
      DF_DEV_DB_PASSWORD: pwd
      DF_DEV_DB_DATABASE: doubtfire-dev
      DF_REDIS_SIDEKIQ_URL: redis://df-compose-redis-sidekiq:6379/0
    volumes:
      - ../doubtfire-api:/doubtfire
      - ../data/student-work:/student-work

  doubtfire-web:
    container_name: doubtfire-web
    build: ../doubtfire-web
    image: lmsdoubtfire/doubtfire-web:10.0.x-dev
    command: /bin/bash -c "npm install --force && npm run start-compose"
    ports:
      - "4200:4200"
    depends_on:
      - doubtfire-api
    volumes:
      - ../doubtfire-web:/doubtfire-web
      - web_node_modules:/doubtfire-web/node_modules

volumes:
  web_node_modules:
  redis_sidekiq_data:
EOF

echo "✔ docker-compose.yml updated."

### ----------------------------------------------------
### 6. Detect Compose version & apply flags
### ----------------------------------------------------
echo "🔍 Checking Docker Compose version..."
COMPOSE_VERSION=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

if [[ "$COMPOSE_VERSION" =~ ^2 ]]; then
    echo "✨ Compose v2 detected — using pretty TTY progress"
    COMPOSE_CMD="docker compose up -d --build --progress=tty"
else
    echo "⚠ Compose not v2 — using fallback"
    COMPOSE_CMD="docker compose up -d --build"
fi

### ----------------------------------------------------
### 7. Start environment
### ----------------------------------------------------
echo "🚀 Starting Doubtfire DEV environment..."
cd /home/$SUDO_USER/doubtfire/doubtfire-deploy/development

$COMPOSE_CMD

echo "====================================================="
echo "   🎉 Doubtfire DEV is now running!"
echo "   🔹 API: http://localhost:3000"
echo "   🔹 Web: http://localhost:4200"
echo "====================================================="
