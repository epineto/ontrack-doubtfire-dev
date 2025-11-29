#!/usr/bin/env bash
set -e

echo "====================================================="
echo "   🚀 Doubtfire LMS – Production Installer v2"
echo "====================================================="

USER_HOME="/home/$SUDO_USER"
INSTALL_DIR="$USER_HOME/doubtfire"
PROD_DIR="$INSTALL_DIR/doubtfire-deploy/production"

### ----------------------------------------------------
### 1. Install Docker & prereqs
### ----------------------------------------------------
echo "📦 Installing Docker Engine..."

apt-get update --fix-missing
apt-get install -y ca-certificates curl gnupg lsb-release --fix-missing

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
 | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
 > /etc/apt/sources.list.d/docker.list

apt-get update --fix-missing
apt-get install -y docker-ce docker-ce-cli containerd.io --fix-missing

systemctl enable docker
systemctl start docker

echo "✔ Docker installed."

### ----------------------------------------------------
### 2. Install Docker Compose v2 (full fix)
### ----------------------------------------------------
echo "🔧 Installing Docker Compose v2..."

mkdir -p /usr/local/libexec/docker/cli-plugins

LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
 | grep browser_download_url \
 | grep docker-compose-linux-x86_64 \
 | cut -d '"' -f 4)

curl -L "$LATEST_COMPOSE" -o /usr/local/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose

ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

echo "✔ Compose installed:"
docker compose version

### ----------------------------------------------------
### 3. Clone Doubtfire production deployment
### ----------------------------------------------------
echo "📥 Cloning production repository..."

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy

cd "$INSTALL_DIR/doubtfire-deploy"
git submodule update --init --recursive

echo "✔ Repositories cloned."

### ----------------------------------------------------
### 4. Patch Dockerfiles
### ----------------------------------------------------
echo "🔧 Patching Dockerfiles..."

for file in $(find . -name Dockerfile); do
  sed -i 's/apt-get update/apt-get update --fix-missing/g' "$file"
  sed -i 's/apt-get install -y/apt-get install -y --fix-missing/g' "$file"
done

echo "✔ Dockerfiles patched."

### ----------------------------------------------------
### 5. Create Nginx reverse proxy inside web container
### ----------------------------------------------------
echo "📝 Writing Nginx config..."

mkdir -p "$PROD_DIR"
cat > "$PROD_DIR/nginx.conf" << 'EOF'
server {
    listen 80;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://apiserver:3000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

### ----------------------------------------------------
### 6. Generate PRODUCTION docker-compose.yml (no external proxy)
### ----------------------------------------------------
echo "📝 Writing production docker-compose.yml..."

cat > "$PROD_DIR/docker-compose.yml" << 'EOF'
services:
  webserver:
    image: lmsdoubtfire/doubtfire-web:10.0.0-3
    platform: linux/amd64
    depends_on:
      - apiserver
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    restart: unless-stopped

  apiserver:
    image: lmsdoubtfire/apiserver:10.0.0-4
    platform: linux/amd64
    env_file:
      - .env.production
    environment:
      RAILS_ENV: production
      RAILS_HOST: localhost
      DF_INSTITUTION_HOST: http://localhost:3000
    ports:
      - "3000:3000"
    depends_on:
      - doubtfire-db
    command: /bin/bash -c "bundle exec rails s -b 0.0.0.0"
    vol
