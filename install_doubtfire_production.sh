#!/usr/bin/env bash
set -e

echo "====================================================="
echo "   🚀 Doubtfire LMS – Automated PRODUCTION Installer"
echo "====================================================="

### ----------------------------------------------------
### 1. Install Docker Engine
### ----------------------------------------------------
echo "🐳 Installing Docker Engine..."

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

systemctl enable docker || true
systemctl start docker || true

echo "✔ Docker installed."


### ----------------------------------------------------
### 2. Install Docker Compose v2
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

# cleanup old versions
rm -f /usr/bin/docker-compose
rm -f /usr/local/bin/docker-compose
ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

echo "✔ Docker Compose installed:"
docker compose version


### ----------------------------------------------------
### 3. Clone Doubtfire Deploy repo (Production)
### ----------------------------------------------------
echo "📥 Cloning doubtfire-deploy repo..."

mkdir -p /home/$SUDO_USER/doubtfire
cd /home/$SUDO_USER/doubtfire

git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy

cd doubtfire-deploy
git submodule update --init --recursive

echo "✔ Repositories cloned."


### ----------------------------------------------------
### 4. Patch Dockerfiles to prevent apt download corruption
### ----------------------------------------------------
echo "🔧 Patching Dockerfiles..."

for file in $(find . -name Dockerfile); do
  sed -i 's/apt-get update/apt-get update --fix-missing/g' "$file"
  sed -i 's/apt-get install -y/apt-get install -y --fix-missing/g' "$file"
done

echo "✔ Dockerfiles patched."


### ----------------------------------------------------
### 5. Generate NEW production docker-compose.yml (no proxy)
### ----------------------------------------------------
echo "📝 Writing new PRODUCTION docker-compose.yml..."

cat > /home/$SUDO_USER/doubtfire/doubtfire-deploy/production/docker-compose.yml <<'EOF'
services:
  webserver:
    image: lmsdoubtfire/doubtfire-web:10.0.0-3
    platform: linux/amd64
    ports:
      - "8080:80"     # Correct mapping for Nginx
    restart: on-failure:5

  apiserver:
    image: lmsdoubtfire/apiserver:10.0.0-4
    platform: linux/amd64
    env_file:
      - .env.production
    ports:
      - "3000:3000"
    depends_on:
      - doubtfire-db
    command: /bin/bash -c "bundle exec rails s -b 0.0.0.0"
    volumes:
      - student_work:/student-work
      - doubtfire_logs:/doubtfire/log
      - ./shared-files:/shared-files
      - ./shared-files/aliases:/etc/aliases:ro
    restart: on-failure:5

  doubtfire-db:
    image: mariadb:10
    restart: always
    environment:
      MARIADB_RANDOM_ROOT_PASSWORD: true
      MARIADB_USER: dfire
      MARIADB_PASSWORD: pwd
      MARIADB_DATABASE: doubtfire
    volumes:
      - mysql_db:/var/lib/mysql

volumes:
  doubtfire_logs: {}
  mysql_db: {}
  student_work: {}
EOF

echo "✔ production docker-compose.yml updated."


### ----------------------------------------------------
### 6. Start Production Environment
### ----------------------------------------------------
echo "🚀 Starting Doubtfire PRODUCTION environment..."

cd /home/$SUDO_USER/doubtfire/doubtfire-deploy/production

docker compose up -d --build

echo "====================================================="
echo "   🎉 Doubtfire PRODUCTION is now running!"
echo "   🌐 Web UI: http://localhost:8080"
echo "   🔧 API:     http://localhost:3000"
echo "====================================================="
