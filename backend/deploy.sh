#!/bin/bash
# ================================================
# callto-backend PM2 Cluster Deploy Script
# Run this on your VPS via SSH to enable cluster mode
# ================================================

echo "🚀 Deploying callto-backend with PM2 Cluster Mode..."

# 1. Install PM2 globally if not already installed
if ! command -v pm2 &> /dev/null; then
    echo "📦 Installing PM2..."
    npm install -g pm2
fi

# 2. Pull the latest changes from GitHub
echo "📥 Pulling latest code..."
git pull origin main

# 3. Install any new dependencies
echo "📦 Installing dependencies..."
npm install

# 4. Create logs directory if not exists (PM2 writes logs here)
mkdir -p logs

# 5. Stop existing PM2 process if running
pm2 stop callto-backend 2>/dev/null || true
pm2 delete callto-backend 2>/dev/null || true

# 6. Start backend in PM2 Cluster Mode using all 4 CPUs
echo "🔥 Starting PM2 Cluster (using all 4 vCPUs)..."
pm2 start ecosystem.config.cjs

# 7. Save PM2 config so it auto-restarts on VPS reboot
pm2 save
pm2 startup

echo ""
echo "✅ Deployment complete!"
echo "📊 To check status: pm2 status"
echo "📋 To view logs:    pm2 logs callto-backend"
echo "🔄 To reload zero-downtime: pm2 reload callto-backend"
