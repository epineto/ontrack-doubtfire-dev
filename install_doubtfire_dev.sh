#!/usr/bin/env bash
set -e

### ----------------------------------------------------
###  NORMALISE LINE ENDINGS (prevents bash^M errors)
### ----------------------------------------------------
sed -i 's/\r$//' "$0"

clear
echo "==============================================="
echo "   Doubtfire DEV Automated Installer"
echo "==============================================="

INSTALL_DIR="$HOME/doubtfire"
REPO_URL="https://github.com/doubtfire-lms/doubtfire-deploy.git"

### ----------------------------------------------------
###  Install Docker + Docker Compose
### ----------------------------------------------------
echo "🐳 Installing Docker..."

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"
newgrp docker <<EOF
EOF

echo "Docker installed ✔"

### ----------------------------------------------------
###  Clone latest dev branch
### ----------------------------------------------------
echo "📦 Cloning Doubtfire deploy repo..."

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [[ ! -d "$INSTALL_DIR/doubtfire-deploy" ]]; then
    git clone --branch 10.0.x --recurse-submodules "$REPO_URL"
else
    echo "Repo already exists. Pulling updates..."
    cd "$INSTALL_DIR/doubtfire-deploy"
    git pull
fi

cd "$INSTALL_DIR/doubtfire-deploy"
git submodule update --init --recursive

### ----------------------------------------------------
###  Patch Dockerfiles (FULL REPLACEMENT MODE)
### ----------------------------------------------------
echo "🔧 Applying safe apt-get patches..."

find "$INSTALL_DIR/doubtfire-deploy" -type f -name "Dockerfile" | while read -r DF; do
    echo "  → Patching $DF"

    # Remove original apt-get block entirely
    sed -i '/apt-get update/{:a;N;/apt-get clean/!ba;d}' "$DF"

    # Insert safe block after first FROM
    sed -i "/^FROM/a RUN apt-get update -y && \\
    apt-get install -y --no-install-recommends --fix-missing \\
        bc \\
        ffmpeg \\
        ghostscript \\
        qpdf \\
        imagemagick \\
        libmagic-dev \\
        libmagickwand-dev \\
        libmariadb-dev \\
        python3-pygments \\
        tzdata \\
        wget \\
        redis \\
        libc6-dev \\
    && rm -rf /var/lib/apt/lists/*" "$DF"
done

echo "✔ All Dockerfiles patched."

### ----------------------------------------------------
###  Update docker-compose.yml
### ----------------------------------------------------
echo "📝 Updating docker-compose.yml..."

DEV_COMPOSE="$INSTALL_DIR/doubtfire-deploy/development/docker-compose.yml"

cat > "$DEV_COMPOSE" <<'EOF'
services:
  doubtfire-web:
    build:
      context: ../doubtfire-web
    ports:
      - "4200:4200"
    environment:
      NODE_ENV: development
    depends_on:
      - doubtfire-api

  doubtfire-api:
    build:
      context: ../doubtfire-api
    environment:
      DB_HOST: doubtfire-dev-db
      DB_USER: dfire
      DB_PASSWORD: pwd
      DB_NAME: doubtfire-dev
    ports:
      - "3000:3000"
    depends_on:
      - doubtfire-dev-db

  doubtfire-dev-db:
    image: mariadb:10
    environment:
      MARIADB_USER: dfire
      MARIADB_PASSWORD: pwd
      MARIADB_DATABASE: doubtfire-dev
    ports:
      - "3306:3306"

  redis-sidekiq:
    image: redis:7
EOF

echo "✔ docker-compose.yml updated."

### ----------------------------------------------------
###  Detect Docker Compose Version & Start Stack
### ----------------------------------------------------
echo "🔍 Checking Docker Compose version..."
COMPOSE_VERSION=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

if [[ "$COMPOSE_VERSION" =~ ^2 ]]; then
    echo "✨ Compose v2 detected — using pretty progress UI"
    COMPOSE_CMD="docker compose up -d --progress=tty"
else
    echo "⚠ Compose v1 detected — forcing pretty UI anyway"
    COMPOSE_CMD="docker-compose up -d"
fi

echo "🚀 Starting Doubtfire DEV environment..."
cd "$INSTALL_DIR/doubtfire-deploy/development"

eval "$COMPOSE_CMD"

echo ""
echo "🎉 Doubtfire DEV is running!"
echo "   Web UI:  http://localhost:4200"
echo "   API:     http://localhost:3000"
echo "   DB:      localhost:3306"
