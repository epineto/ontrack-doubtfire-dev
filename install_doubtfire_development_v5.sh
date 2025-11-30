#!/usr/bin/env bash
set -e

# ============================================================
#  DOUBTFIRE DEVELOPMENT ENVIRONMENT INSTALLER v5 (Ubuntu)
#  - MariaDB 10.6
#  - Node 18 Frontend (Fully Working)
#  - Angular Binds to 0.0.0.0
#  - Permissions Fix
#  - Healthchecks Fixed
#  - node_modules Volume Reset
# ============================================================

echo "============================================================"
echo "         DOUBTFIRE DEVELOPMENT INSTALLER v5"
echo "============================================================"
echo ""

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run this with sudo:"
  echo "   sudo ./install_doubtfire_development_v5.sh"
  exit 1
fi

# ------------------------------------------------------------
# System Packages
# ------------------------------------------------------------
echo "🔄 Updating system..."
apt-get update -y
apt-get upgrade -y

echo "📦 Installing required packages..."
apt-get install -y \
  ca-certificates curl gnupg lsb-release git apt-transport-https \
  build-essential

# ------------------------------------------------------------
# Install Docker
# ------------------------------------------------------------
echo "🐳 Installing Docker Engine & Compose..."

if ! command -v docker >/dev/null 2>&1; then
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
  echo "✔ Docker already installed."
fi

systemctl enable docker
systemctl start docker

# Ensure user in docker group
if ! groups "$SUDO_USER" | grep -q docker; then
  usermod -aG docker "$SUDO_USER"
  echo "👤 Added $SUDO_USER to docker group."
fi

echo "✔ Docker is ready."
echo ""

# ------------------------------------------------------------
# Clone Repos
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

echo "🗑 Removing default submodules..."
rm -rf "$DEPLOY_DIR/doubtfire-api"
rm -rf "$DEPLOY_DIR/doubtfire-web"

echo "📥 Cloning Doubtfire API..."
git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-api.git \
  "$DEPLOY_DIR/doubtfire-api"

echo "📥 Cloning Doubtfire Web..."
git clone --branch 10.0.x https://github.com/doubtfire-lms/doubtfire-web.git \
  "$DEPLOY_DIR/doubtfire-web"

echo "✔ Repos ready."
echo ""

# ------------------------------------------------------------
# Fix Frontend Permissions
# ------------------------------------------------------------
echo "🔧 Fixing frontend file permissions..."
chown -R "$SUDO_USER:$SUDO_USER" "$DEPLOY_DIR/doubtfire-web"

# ------------------------------------------------------------
# Replace Web Dockerfile Automatically (Node 18)
# ------------------------------------------------------------
echo "🛠 Injecting patched Web Dockerfile (Node 18)..."

WEB_DOCKERFILE="$DEPLOY_DIR/doubtfire-web/Dockerfile"

cat > "$WEB_DOCKERFILE" << 'EOF'
FROM node:18

WORKDIR /doubtfire-web

COPY package*.json ./

RUN npm install --legacy-peer-deps --no-audit --no-fund

COPY . .

EXPOSE 4200

CMD ["npm", "start"]
EOF

echo "✔ Web Dockerfile updated."
echo ""

# ------------------------------------------------------------
# Write Updated docker-compose.yml
# ------------------------------------------------------------
echo "🛠 Updating docker-compose.yml..."

COMPOSE_DIR="$DEPLOY_DIR/development"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

mkdir -p "$COMPOSE_DIR"

cat > "$COMPOSE_FILE" << 'EOF'
services:

  dev-db:
    container_name: doubtfire-dev-db
    image: mariadb:10.6
    environment:
      MYSQL_ROOT_PASSWORD: db-root-password
      MYSQL_DATABASE: doubtfire-dev
      MYSQL_USER: dfire
      MYSQL_PASSWORD: pwd
    volumes:
      - ../data/database:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mysql -udfire -ppwd -e 'SELECT 1'"]
      interval: 5s
      timeout: 5s
      retries: 30

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
    ports:
      - "4200:4200"
    depends_on:
      - doubtfire-api
    user: root
    command: >
      bash -c "npm install --legacy-peer-deps --no-audit --no-fund &&
               npx ng serve --host 0.0.0.0 --disable-host-check"
    volumes:
      - ../doubtfire-web:/doubtfire-web
      - web_node_modules:/doubtfire-web/node_modules

volumes:
  web_node_modules:
  redis_sidekiq_data:
EOF

echo "✔ Compose file updated."
echo ""

# ------------------------------------------------------------
# Reset node_modules Volume
# ------------------------------------------------------------
echo "🗑 Resetting web_node_modules volume..."
docker compose -f "$COMPOSE_FILE" down || true
docker volume rm development_web_node_modules || true
echo "✔ Volume reset."
echo ""

# ------------------------------------------------------------
# Start Containers
# ------------------------------------------------------------
echo "🚀 Starting all containers..."
docker compose -f "$COMPOSE_FILE" up -d --build

echo "⏳ Waiting for DB to become healthy..."
sleep 15

echo "🔁 Checking DB connectivity..."
for i in {1..30}; do
  if docker compose -f "$COMPOSE_FILE" exec dev-db mysql -udfire -ppwd -e "SELECT 1" >/dev/null 2>&1; then
    echo "✔ Database ready!"
    break
  fi
  echo "⏳ Still waiting ($i/30)..."
  sleep 3
done

# ------------------------------------------------------------
# Run Rails Setup
# ------------------------------------------------------------
echo "🛠 Running Rails migrations & DB populate..."

docker compose -f "$COMPOSE_FILE" exec doubtfire-api bash -c "
  bundle install &&
  bundle exec rails db:environment:set RAILS_ENV=development &&
  bundle exec rake db:reset db:migrate &&
  bundle exec rake db:populate
"

echo ""
echo "============================================================"
echo " 🎉 DOUBTFIRE DEVELOPMENT ENVIRONMENT READY (v5) 🎉"
echo "============================================================"
echo "Frontend: http://localhost:4200"
echo "Backend:  http://localhost:3000/api/docs"
echo ""
echo "Default users:"
echo "  admin: aadmin / password"
echo "  convenor: aconvenor / password"
echo "  tutor: atutor / password"
echo "  student: student_1 / password"
echo ""
echo "⚠ Re-login to apply Docker group membership."
echo "============================================================"
