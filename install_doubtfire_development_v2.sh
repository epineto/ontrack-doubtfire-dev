#!/usr/bin/env bash
set -e

# ============================================================
#  DOUBTFIRE DEVELOPMENT ENVIRONMENT INSTALLER (Ubuntu)
#  Author: Epi Neto
#  Version: v2
# ============================================================

echo "============================================================"
echo "         DOUBTFIRE DEVELOPMENT INSTALLER (Ubuntu)"
echo "============================================================"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script with sudo:"
  echo "   sudo ./install_doubtfire_development_v2.sh"
  exit 1
fi

# ------------------------------------------------------------
# Update System
# ------------------------------------------------------------
echo "🔄 Updating system packages..."
apt-get update -y
apt-get upgrade -y

# ------------------------------------------------------------
# Install Prerequisites
# ------------------------------------------------------------
echo "📦 Installing required utilities..."
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  apt-transport-https \
  build-essential

# ------------------------------------------------------------
# Install Docker Engine + Compose v2
# ------------------------------------------------------------
echo "🐳 Installing Docker + Docker Compose v2..."

if ! command -v docker &> /dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y

  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
else
  echo "✔ Docker already installed"
fi

# Enable Docker daemon
systemctl enable docker
systemctl start docker

# Add user to docker group
if ! groups $SUDO_USER | grep -q docker; then
  usermod -aG docker $SUDO_USER
  echo "👤 Added $SUDO_USER to docker group."
fi

# Verify docker
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker daemon is not running."
  exit 1
fi

echo "✔ Docker & Compose installed successfully."
echo ""

# ------------------------------------------------------------
# Begin Doubtfire Installation
# ------------------------------------------------------------

INSTALL_DIR="/opt/doubtfire"
echo "📁 Creating installation directory at $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

cd "$INSTALL_DIR"

# ------------------------------------------------------------
# Clone Official Repositories
# ------------------------------------------------------------
echo "📥 Cloning official Doubtfire repositories (10.0.x)..."

if [ ! -d "doubtfire-deploy" ]; then
  git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy
else
  echo "✔ doubtfire-deploy already exists."
fi

DEPLOY_DIR="$INSTALL_DIR/doubtfire-deploy"

# Replace submodules
echo "🗑️ Removing existing API & WEB submodules..."
rm -rf "$DEPLOY_DIR/doubtfire-api"
rm -rf "$DEPLOY_DIR/doubtfire-web"

echo "📥 Cloning new API & WEB repositories..."

git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-api.git "$DEPLOY_DIR/doubtfire-api"
git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-web.git "$DEPLOY_DIR/doubtfire-web"

echo "✔ Repositories ready."
echo ""

# ------------------------------------------------------------
# Replace Docker Compose File
# ------------------------------------------------------------
echo "🛠 Updating docker-compose.yml..."

COMPOSE_DIR="$DEPLOY_DIR/development"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

mkdir -p "$COMPOSE_DIR"

if [ -f "$COMPOSE_FILE" ]; then
  mv "$COMPOSE_FILE" "$COMPOSE_FILE.bak"
  echo "📦 Backed up old docker-compose.yml → docker-compose.yml.bak"
fi

cat > "$COMPOSE_FILE" << 'EOF'
services:

  dev-db:
    container_name: doubtfire-dev-db
    image: mariadb
    environment:
      MYSQL_ROOT_PASSWORD: db-root-password
      MYSQL_DATABASE: doubtfire-dev
      MYSQL_USER: dfire
      MYSQL_PASSWORD: pwd
    volumes:
      - ../data/database:/var/lib/mysql

  redis-sidekiq:
    container_name: doubtfire-redis-sidekiq
    image: redis:7.0
    volumes:
      - redis_sidekiq_data:/data

  doubtfire-api:
    container_name: doubtfire-api
    build: ../doubtfire-api
    image: doubtfire-api:10.0-dev
    ports:
      - "3000:3000"
    volumes:
      - ../doubtfire-api:/doubtfire
      - ../data/tmp:/doubtfire/tmp
      - ../data/student-work:/student-work
    depends_on:
      - dev-db
      - redis-sidekiq
    environment:
      RAILLS_ENV: development

      DF_STUDENT_WORK_DIR: /student-work
      DF_INSTITUTION_HOST: http://localhost:3000
      DF_INSTITUTION_PRODUCT_NAME: OnTrack

      DF_SECRET_KEY_BASE: test-secret-key-test-secret-key!
      DF_SECRET_KEY_ATTR: test-secret-key-test-secret-key!
      DF_SECRET_KEY_DEVISE: test-secret-key-test-secret-key!

      DF_AUTH_METHOD: database

      DF_DEV_DB_ADAPTER: mysql2
      DF_DEV_DB_HOST: doubtfire-dev-db
      DF_DEV_DB_DATABASE: doubtfire-dev
      DF_DEV_DB_USERNAME: dfire
      DF_DEV_DB_PASSWORD: pwd

      DF_TEST_DB_ADAPTER: mysql2
      DF_TEST_DB_HOST: doubtfire-dev-db
      DF_TEST_DB_DATABASE: doubtfire-dev
      DF_TEST_DB_USERNAME: dfire
      DF_TEST_DB_PASSWORD: pwd

      DF_PRODUCTION_DB_ADAPTER: mysql2
      DF_PRODUCTION_DB_HOST: doubtfire-dev-db
      DF_PRODUCTION_DB_DATABASE: doubtfire-dev
      DF_PRODUCTION_DB_USERNAME: dfire
      DF_PRODUCTION_DB_PASSWORD: pwd

      OVERSEER_ENABLED: 0
      TII_ENABLED: false

      DF_REDIS_SIDEKIQ_URL: redis://doubtfire-redis-sidekiq:6379/0

  doubtfire-web:
    container_name: doubtfire-web
    build: ../doubtfire-web
    image: doubtfire-web:10.0-dev
    command: /bin/bash -c "npm install && npm start"
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

echo "✔ Docker Compose updated."
echo ""

# ------------------------------------------------------------
# Start Environment
# ------------------------------------------------------------
echo "🚀 Starting Doubtfire environment..."

cd "$COMPOSE_DIR"

docker compose up -d --build

echo "⏳ Waiting for containers to be ready..."
sleep 15

# ------------------------------------------------------------
# Run DB Migrations + Populate
# ------------------------------------------------------------
echo "🛠 Running DB migrations and populate..."

docker compose exec doubtfire-api bash -c "
  bundle install &&
  bundle exec rails db:environment:set RAILS_ENV=development &&
  bundle exec rake db:reset db:migrate &&
  bundle exec rake db:populate
"

echo "✔ Database ready."
echo ""

# ------------------------------------------------------------
# All Done
# ------------------------------------------------------------
echo "============================================================"
echo "            🎉 DOUBTFIRE IS READY TO USE 🎉"
echo "============================================================"
echo ""
echo "➡ API:  http://localhost:3000/api/docs/"
echo "➡ Web:  http://localhost:4200"
echo ""
echo "Default users:"
echo "  • Admin: aadmin / password"
echo "  • Convenor: aconvenor / password"
echo "  • Tutor: atutor / password"
echo "  • Student: student_1 / password"
echo ""
echo "============================================================"
echo "IMPORTANT: Logout & login again so Docker permissions apply."
echo "============================================================"
