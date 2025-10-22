#!/bin/bash

set -e  # Exit immediately on error
LOG_FILE="deploy_$(date +'%Y%m%d_%H%M%S').log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
  log "❌ ERROR: $1"
  exit 1
}

# ========== 1. COLLECT USER INPUTS ==========
read -p "Enter your GitHub repo URL: " REPO_URL
read -p "Enter your GitHub Personal Access Token: " PAT
read -p "Enter branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter SSH username for remote server: " SSH_USER
read -p "Enter remote server IP: " SERVER_IP
read -p "Enter path to SSH key: " SSH_KEY
read -p "Enter application port (inside container): " APP_PORT

# ========== 2. CLONE OR UPDATE REPO ==========
REPO_NAME=$(basename "$REPO_URL" .git)

if [ -d "$REPO_NAME" ]; then
  log "Repo exists. Pulling latest changes..."
  cd "$REPO_NAME"
  git pull || error_exit "Git pull failed."
else
  log "Cloning repository..."
  git clone https://$PAT@${REPO_URL#https://} || error_exit "Git clone failed."
  cd "$REPO_NAME"
fi

git checkout "$BRANCH" || error_exit "Branch switch failed."

# Verify Dockerfile
if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
  error_exit "No Dockerfile or docker-compose.yml found."
fi
log "✅ Docker file found."

# ========== 3. SSH CONNECTIVITY TEST ==========
log "Testing SSH connection to $SERVER_IP..."
ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" "echo Connection OK" || error_exit "SSH connection failed."

# ========== 4. PREPARE REMOTE ENVIRONMENT ==========
log "Preparing remote environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
set -e
sudo apt update -y
sudo apt install -y docker docker-compose nginx
sudo systemctl enable docker --now
sudo usermod -aG docker \$USER
EOF

# ========== 5. TRANSFER FILES ==========
log "Transferring project files..."
rsync -avz -e "ssh -i $SSH_KEY" ./ "$SSH_USER@$SERVER_IP:~/app/"

# ========== 6. DEPLOY DOCKER CONTAINER ==========
log "Deploying Docker container..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
cd ~/app
if [ -f docker-compose.yml ]; then
  sudo docker-compose down || true
  sudo docker-compose up -d --build
else
  sudo docker stop app || true
  sudo docker rm app || true
  sudo docker build -t app .
  sudo docker run -d -p $APP_PORT:$APP_PORT --name app app
fi
EOF

# ========== 7. CONFIGURE NGINX REVERSE PROXY ==========
log "Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
sudo bash -c 'cat > /etc/nginx/sites-available/app <<EOL
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL'
sudo ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
EOF

# ========== 8. VALIDATE DEPLOYMENT ==========
log "Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
sudo docker ps
curl -I http://localhost
EOF

log "✅ Deployment successful!"
