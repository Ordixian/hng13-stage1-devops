#!/bin/bash
# ========================================
# HNG13 Stage 1 - Automated Deployment Script
# Author: Ojomu Gbolahan Fadilulahi (@Ordixian)
# ========================================

set -e  # exit immediately on error
LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"

echo "🚀 Starting deployment..." | tee -a "$LOGFILE"

# 1️⃣ Collect user input
read -p "Enter GitHub repo URL: " REPO_URL
read -p "Enter your Personal Access Token (PAT): " PAT
read -p "Enter branch name [default: main]: " BRANCH
BRANCH=${BRANCH:-main}
read -p "Enter remote server username: " USERNAME
read -p "Enter remote server IP: " SERVER_IP
read -p "Enter SSH key path: " KEY_PATH
read -p "Enter internal app port (e.g. 5000): " APP_PORT

echo "[INFO] Inputs received." | tee -a "$LOGFILE"

# 2️⃣ Clone repository
if [ -d "repo" ]; then
    echo "[INFO] Repo exists. Pulling latest changes..." | tee -a "$LOGFILE"
    cd repo && git pull origin "$BRANCH"
else
    echo "[INFO] Cloning repository..." | tee -a "$LOGFILE"
    git clone -b "$BRANCH" "https://${PAT}@${REPO_URL#https://}" repo
    cd repo
fi

# 3️⃣ Verify Dockerfile or docker-compose.yml
if [ -f Dockerfile ] || [ -f docker-compose.yml ]; then
    echo "[INFO] Deployment file found." | tee -a "$LOGFILE"
else
    echo "[ERROR] No Dockerfile or docker-compose.yml found!" | tee -a "$LOGFILE"
    exit 1
fi

# 4️⃣ SSH into server & setup environment
echo "[INFO] Setting up remote server..." | tee -a "$LOGFILE"
ssh -i "$KEY_PATH" "$USERNAME@$SERVER_IP" <<EOF
    sudo apt update -y
    sudo apt install -y docker.io docker-compose nginx
    sudo systemctl enable docker nginx
    sudo systemctl start docker nginx
EOF

echo "[INFO] Remote environment ready." | tee -a "$LOGFILE"

echo "✅ Deployment skeleton completed (expand next session)." | tee -a "$LOGFILE"
