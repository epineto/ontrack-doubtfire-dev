#!/usr/bin/env bash
set -e

# ============================================================
#  DOUBTFIRE DEVELOPMENT ENVIRONMENT INSTALLER v3 (Ubuntu)
#  Fully patched with DB healthcheck + migration retry logic
# ============================================================

echo "============================================================"
echo "            DOUBTFIRE DEVELOPMENT INSTALLER v3"
echo "============================================================"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script with sudo:"
  echo "    sudo ./install_doubtfire_development_v3.sh"
  exit 1
fi

# ------------------------------------------------------------
# System Prep
# ------------------------------------------------------------
echo "🔄 Updating system..."
apt-get update -y
apt-get upgrade -y

echo "📦 Installing dependencies..."
apt-get install -y \
  ca-certificates curl gnupg lsb-release git apt-transport-https \
  build-essential

# ------------------------------------------------------------
# Install Docker + Compose v2
# ------------------------------------------------------------
echo "🐳 Installing Docker Engine and Compose v2..."

if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor \
    -o /etc/apt/keyrings/docker.gpg

  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y

  apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
else
  echo "✔ Docker already installed"
fi

systemctl enable docker
systemctl start docker

if ! groups $SUDO_USER | grep -q docker; then
  usermod -aG docker $SUDO_USER
  echo "👤 Added $SUDO_USER to docker group."
fi

echo "✔ Docker & Compose ready"
echo ""

# ------------------------------------------------------------
# Clone Repositories
# ------------------------------------------------------------
INSTALL_DIR="/opt/doubtfire"
DEPLOY_DIR="$INSTALL_DIR/doubtfire-deploy"

echo "📁 Creating install directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "📥 Cloning Doubtfire Deploy (10.0.x)..."
if [ ! -d "$DEPLOY_DIR" ]; then
  git clone --branch 10.0.x --recurse-submodules \
    https://github.com/doubtfire-lms/doubtfire-deploy
else
  echo "✔ doubtfire-deploy already exists."
fi

echo "🗑️ Removing bundled submodules..."
rm -rf "$DEPLOY_DIR/doubtfire-api"
rm -rf "$DEPLOY_DIR/doubtfire-web"

echo "📥 Cloning API (10.0.x)..."
git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-api.git \
  "$DEPLOY_DIR/doubtfire-api"

echo "📥 Cloning Web (10.0.x)..."
git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-web.git \
  "$DEPLOY_DIR/doubtfire-web"

echo "✔ Repository replacement complete"
echo ""

# ------------------------------------------------------------
# Replace docker-compose.yml
# ------------------------------------------------------------
echo "🛠 Updating Docker Compose file..."

COMPOSE_DIR="$DEPLOY_DIR/development"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

mkdir -p "$COMPOSE_DIR"

[ -f "$COMPOSE_FILE" ] && mv "$COMPOSE_FILE" "$COMPOSE_FILE.bak"

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
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 5s
      timeout: 5s
      retries: 20

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
    depends_on:
      dev-db:
        condition: service_healthy
      redis-sidekiq:
        condition: service_started
    volumes:
      - ../doubtfire-api:/doubtfire
      - ../data/tmp:/doubtfire/tmp
      - ../data/student-work:/student-work
    environment:
      RAILS_ENV: development

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

echo "✔ Docker Compose rebuilt"
echo ""

# ------------------------------------------------------------
# Start Containers
# ------------------------------------------------------------
echo "🚀 Starting containers..."
cd "$COMPOSE_DIR"

docker compose down || true
docker compose up -d --build

echo "⏳ Waiting for DB healthcheck..."
sleep 10

# ------------------------------------------------------------
# Retry DB connection before migrations
# ------------------------------------------------------------
echo "🔁 Checking DB readiness inside API container..."

for i in {1..30}; do
  if docker compose exec doubtfire-api bash -c "mysqladmin ping -h doubtfire-dev-db --silent"; then
    echo "✔ Database is ready!"
    break
  fi
  echo "⏳ DB not ready yet... attempt $i/30"
  sleep 3
done

# ------------------------------------------------------------
# Run Migrations + Populate DB
# ------------------------------------------------------------
echo "🛠 Running Rails migrations & populate..."

docker compose exec doubtfire-api bash -c "
  bundle install &&
  bundle exec rails db:environment:set RAILS_ENV=development &&
  bundle exec rake db:reset db:migrate &&
  bundle exec rake db:populate
"

echo ""
echo "============================================================"
echo " 🎉 DOUBTFIRE DEVELOPMENT ENVIRONMENT IS READY (v3) 🎉"
echo "============================================================"
echo "Web UI:  http://localhost:4200"
echo "API Docs: http://localhost:3000/api/docs"
echo ""
echo "Default accounts:"
echo "  admin: aadmin / password"
echo "  convenor: aconvenor / password"
echo "  tutor: atutor / password"
echo "  student: student_1 / password"
echo ""
echo "⚠ Logout/login so Docker group membership applies."
echo "============================================================"
