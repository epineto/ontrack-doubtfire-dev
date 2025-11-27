#!/usr/bin/env bash
set -e

###############################################################################
# FIX WINDOWS CRLF IF PRESENT
###############################################################################
sed -i 's/\r$//' "$0" 2>/dev/null || true

echo "🔥 Installing Doubtfire DEV (10.0.x-dev) environment..."

###############################################################################
# SYSTEM SETUP
###############################################################################
echo "📦 Updating system packages..."
sudo apt-get update -y

echo "🐳 Installing Docker & Docker Compose..."
sudo snap install docker || sudo apt-get install -y docker.io docker-compose-plugin

###############################################################################
# CLONE REPOS
###############################################################################
echo "📁 Creating workspace at ~/doubtfire..."
mkdir -p ~/doubtfire
cd ~/doubtfire

echo "⬇️ Cloning Doubtfire Deploy (10.0.x branch)..."
if [ ! -d "doubtfire-deploy" ]; then
  git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy
fi

###############################################################################
# WRITE docker-compose.yml
###############################################################################
echo "📝 Writing updated docker-compose.yml..."

cat > ~/doubtfire/doubtfire-deploy/development/docker-compose.yml <<'EOF'
services:
  dev-db:
    container_name: df-compose-dev-db
    image: mariadb:10.11
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
    container_name: df-compose-redis-sidekiq
    image: redis:7.0
    volumes:
      - redis_sidekiq_data:/data

  doubtfire-api:
    container_name: doubtfire-api
    build:
      context: ../doubtfire-api
      dockerfile: Dockerfile
      args:
        RAILS_ENV: development
    image: lmsdoubtfire/doubtfire-api:10.0.x-dev
    ports:
      - "3000:3000"
    environment:
      RAILS_ENV: development

      DF_DEV_DB_ADAPTER: mysql2
      DF_DEV_DB_HOST: df-compose-dev-db
      DF_DEV_DB_DATABASE: doubtfire-dev
      DF_DEV_DB_USERNAME: dfire
      DF_DEV_DB_PASSWORD: pwd

      DF_REDIS_SIDEKIQ_URL: redis://df-compose-redis-sidekiq:6379/0

      DF_STUDENT_WORK_DIR: /student-work
      DF_INSTITUTION_HOST: http://localhost:3000
      DF_INSTITUTION_PRODUCT_NAME: OnTrack

      DF_SECRET_KEY_BASE: test-secret-key-test-secret-key!
      DF_SECRET_KEY_ATTR: test-secret-key-test-secret-key!
      DF_SECRET_KEY_DEVISE: test-secret-key-test-secret-key!

      OVERSEER_ENABLED: 0
      TII_ENABLED: false

    volumes:
      - ../doubtfire-api:/doubtfire
      - ../data/tmp:/doubtfire/tmp
      - ../data/student-work:/student-work
    depends_on:
      - dev-db
      - redis-sidekiq

  doubtfire-web:
    container_name: doubtfire-web
    build:
      context: ../doubtfire-web
      dockerfile: Dockerfile
      args:
        NODE_VERSION: "20.11.1"
    image: lmsdoubtfire/doubtfire-web:10.0.x-dev
    command: >
      bash -lc "
        rm -rf node_modules package-lock.json &&
        npm install &&
        npm rebuild &&
        ng serve --host 0.0.0.0 --poll 2000 --disable-host-check
      "
    ports:
      - "4200:4200"
    volumes:
      - ../doubtfire-web:/doubtfire-web
      - web_node_modules:/doubtfire-web/node_modules
    depends_on:
      - doubtfire-api

volumes:
  web_node_modules:
  redis_sidekiq_data:
EOF

###############################################################################
# DOCKER COMPOSE COMPAT MODE
###############################################################################
echo "🔍 Checking Docker Compose availability..."

if docker compose version >/dev/null 2>&1; then
    echo "✨ Docker Compose recognized — using: docker compose up -d --build"
    COMPOSE_CMD="docker compose up -d --build"
elif docker-compose version >/dev/null 2>&1; then
    echo "⚠ Using legacy docker-compose — enabling fallback UI"
    COMPOSE_CMD="docker-compose up -d --build"
else
    echo "❌ ERROR: No docker compose available"
    exit 1
fi

###############################################################################
# START STACK
###############################################################################
echo "🚀 Starting Doubtfire DEV environment..."
cd ~/doubtfire/doubtfire-deploy/development
sudo $COMPOSE_CMD

echo "📡 Streaming logs (Ctrl+C to stop)..."
sudo $COMPOSE_CMD logs -f || sudo docker compose logs -f
