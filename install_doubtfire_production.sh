#!/usr/bin/env bash
set -e

echo "====================================================="
echo "   🚀 Doubtfire LMS – Automated PRODUCTION Installer"
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

# Remove any old version
rm -f /usr/local/bin/docker-compose
ln -s /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

echo "✔ Docker Compose v2 installed:"
docker compose version


### ----------------------------------------------------
### 3. Clone Doubtfire Deploy (Production)
### ----------------------------------------------------
echo "📥 Cloning doubtfire-deploy repo (production)..."

mkdir -p /opt/doubtfire
cd /opt/doubtfire

git clone --branch 10.0.x --recurse-submodules https://github.com/doubtfire-lms/doubtfire-deploy

cd doubtfire-deploy
git submodule update --init --recursive

echo "✔ Repositories cloned."


### ----------------------------------------------------
### 4. Patch Dockerfiles (Fix apt-get issues)
### ----------------------------------------------------
echo "🔧 Patching Dockerfiles..."

for file in $(find . -name Dockerfile); do
  echo "Patching $file"
  sed -i 's/apt-get update/apt-get update --fix-missing/g' "$file"
  sed -i 's/apt-get install -y/apt-get install -y --fix-missing/g' "$file"
done

echo "✔ Dockerfiles patched."


### ----------------------------------------------------
### 5. Create PRODUCTION docker-compose.yml (NO PROXY)
### ----------------------------------------------------
echo "📝 Writing production docker-compose.yml..."

cat > /opt/doubtfire/doubtfire-deploy/production/docker-compose.yml <<'EOF'
services:
  webserver:
    platform: linux/amd64
    image: lmsdoubtfire/doubtfire-web:10.0.0-3
    ports:
      - "8080:8080"
    networks:
      - backnet
    restart: on-failure:5

  apiserver:
    platform: linux/amd64
    image: lmsdoubtfire/apiserver:10.0.0-4
    env_file:
      - .env.production
    ports:
      - "3000:3000"
    networks:
      - backnet
    depends_on:
      - doubtfire-db
    volumes:
      - student_work:/student-work
      - doubtfire_logs:/doubtfire/log
      - ./shared-files:/shared-files
      - ./shared-files/aliases:/etc/aliases:ro
    command: /bin/bash -c "bundle exec rails s -b 0.0.0.0"
    restart: on-failure:5

  doubtfire-db:
    image: mariadb:10
    restart: always
    networks:
      - backnet
    environment:
      MARIADB_RANDOM_ROOT_PASSWORD: true
      MARIADB_USER: dfire
      MARIADB_PASSWORD: pwd
      MARIADB_DATABASE: doubtfire
    volumes:
      - mysql_db:/var/lib/mysql

networks:
  backnet:

volumes:
  latex_tmp: {}
  redis_data: {}
  doubtfire_logs: {}
  mysql_db: {}
  student_work: {}
EOF

echo "✔ Production docker-compose.yml ready."


### ----------------------------------------------------
### 6. Start Production services
### ----------------------------------------------------
echo "🚀 Starting Doubtfire PRODUCTION environment..."

cd /opt/doubtfire/doubtfire-deploy/production

# NO MORE --progress FLAG
docker compose up -d --build

echo "====================================================="
echo "   🎉 Doubtfire PRODUCTION is now running!"
echo "====================================================="
echo "   🌐 Web UI:   http://localhost:8080"
echo "   🔧 API:      http://localhost:3000"
echo "====================================================="
