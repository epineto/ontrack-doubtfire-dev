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
# CREATE WORKSPACE
###############################################################################
echo "📁 Creating workspace at ~/doubtfire..."
mkdir -p ~/doubtfire
cd ~/doubtfire

###############################################################################
# CLONE REPO
###############################################################################
echo "⬇️ Cloning Doubtfire Deploy (10.0.x branch)..."
if [ ! -d "doubtfire-deploy" ]; then
  git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy
fi

###############################################################################
# PATCH DOCKERFILE (Fix Debian mirror fetch errors)
###############################################################################
API_DOCKERFILE="$HOME/doubtfire/doubtfire-deploy/doubtfire-api/Dockerfile"

echo "🔧 Applying Dockerfile reliability patch..."
if [[ -f "$API_DOCKERFILE" ]]; then
    cp "$API_DOCKERFILE" "${API_DOCKERFILE}.bak"

    sed -i '/apt-get update/,+25c\
RUN sed -i '\''s|deb.debian.org|ftp.debian.org|g'\'' /etc/apt/sources.list \\
  && until apt-get update --fix-missing; do \\
       echo \"Retrying apt-get update...\"; sleep 3; \\
     done \\
  && apt-get install -y --fix-missing \\
       bc \\
       ffmpeg \\
       ghostscript qpdf \\
       imagemagick \\
       libmagic-dev \\
       libmagickwand-dev \\
       libmariadb-dev \\
       python3-pygments \\
       tzdata \\
       wget \\
       redis \\
       libc6-dev \\
       docker-ce \\
       docker-ce-cli \\
       containerd.io \\
  && apt-get clean' "$API_DOCKERFILE"

    echo "✅ Dockerfile patched successfully!"
else
    echo "❌ ERROR: Dockerfile not found at $API_DOCKERFILE"
fi

###############################################################################
# WRITE UPDATED docker-compose.yml
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
# DOCKER COMPOSE PROGRESS UI HANDLING
###############################################################################
echo "🔍 Detecting Docker Compose version..."

export COMPOSE_PROGRESS=auto
export COMPOSE_DISABLE_SPINNER=false

# Default command
COMPOSE_CMD="sudo docker compose up -d --build"

if docker compose version >/dev/null 2>&1; then
    echo "✨ Docker Compose v2 detected — enabling pretty progress UI!"
    COMPOSE_CMD="sudo docker compose up -d --build --progress=tty"
elif docker-compose version >/dev/null 2>&1; then
    echo "⚠ Docker Compose v1 detected — using fallback (simulated UI)"
    COMPOSE_CMD="sudo docker-compose up -d --build"
else
    echo "❌ No Docker Compose found"
    exit 1
fi

###############################################################################
# START STACK
###############################################################################
echo "🚀 Starting Doubtfire DEV environment..."
cd ~/doubtfire/doubtfire-deploy/development
$COMPOSE_CMD

echo "📡 Streaming logs (Ctrl+C to stop)..."
docker compose logs -f || docker-compose logs -f
