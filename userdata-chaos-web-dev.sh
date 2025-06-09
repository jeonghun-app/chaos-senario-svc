#!/bin/bash

# AWS Bank Demo - bank-chaos-web Development UserData Script
# This script sets up only bank-chaos-web with npm run dev

LOG_FILE="/var/log/userdata-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "====================================="
echo "Bank Chaos Web Development Setup Started"
echo "Timestamp: $(date)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "====================================="

# 오류 발생시 즉시 종료
set -e

# 스왑 파일 생성 (메모리가 부족한 경우 대비)
if [ ! -f /swapfile ]; then
    echo "Creating swap file for development..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1024 count=2097152
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "✅ Swap file created"
fi

# Node.js 메모리 제한 설정
export NODE_OPTIONS="--max-old-space-size=2048"

# RPM lock 대기 함수
wait_for_rpm() {
    for i in {1..30}; do
        if ! pgrep -x "dnf\|yum\|rpm" > /dev/null && ! fuser /var/lib/rpm/.rpm.lock > /dev/null 2>&1; then
            return 0
        fi
        echo "Waiting for package manager... ($i/30)"
        sleep 10
    done
    pkill -f "dnf\|yum\|rpm" || true
    rm -f /var/lib/rpm/.rpm.lock || true
}

# 패키지 설치
echo "Installing packages..."
wait_for_rpm
dnf update -y || echo "Update failed, continuing..."

wait_for_rpm
dnf install -y git wget unzip htop jq nodejs npm --allowerasing || {
    echo "Some packages failed, trying individually..."
    dnf install -y nodejs npm || {
        echo "CRITICAL: Failed to install Node.js/npm"
        exit 1
    }
}

# Node.js 버전 확인
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# PM2 설치 (전역)
echo "Installing PM2 globally..."
npm install -g pm2 || {
    echo "CRITICAL: Failed to install PM2"
    exit 1
}

# 환경 변수 설정
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AWS_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Environment variables:"
echo "  INSTANCE_ID: $INSTANCE_ID"
echo "  AWS_AVAILABILITY_ZONE: $AWS_AVAILABILITY_ZONE"
echo "  AWS_REGION: $AWS_REGION"
echo "  PRIVATE_IP: $PRIVATE_IP"

# 애플리케이션 디렉토리 생성
mkdir -p /opt/bank-chaos-web
cd /opt/bank-chaos-web

# GitHub에서 코드 다운로드
echo "Downloading bank-chaos-web code..."
for i in {1..3}; do
    rm -rf /opt/bank-chaos-web/* 2>/dev/null || true
    echo "Download attempt $i/3..."
    if git clone https://github.com/jeonghun-app/chaos-senario-svc.git /tmp/repo; then
        if [ -d "/tmp/repo/bank-chaos-web" ]; then
            cp -r /tmp/repo/bank-chaos-web/* /opt/bank-chaos-web/
            echo "bank-chaos-web repository downloaded successfully"
            rm -rf /tmp/repo
            break
        else
            echo "bank-chaos-web directory not found in repository"
            rm -rf /tmp/repo
            if [ $i -eq 3 ]; then
                echo "CRITICAL: bank-chaos-web directory not found after 3 attempts"
                exit 1
            fi
        fi
    elif [ $i -eq 3 ]; then
        echo "CRITICAL: Failed to download repository after 3 attempts"
        exit 1
    fi
    sleep 10
done

# 환경 변수 파일 생성
cat > /opt/bank-chaos-web/.env.local << EOF
INSTANCE_ID=$INSTANCE_ID
AWS_AVAILABILITY_ZONE=$AWS_AVAILABILITY_ZONE
AWS_REGION=$AWS_REGION
PRIVATE_IP=$PRIVATE_IP
NODE_ENV=development
PORT=3000
NEXT_TELEMETRY_DISABLED=1
LOG_LEVEL=debug
EOF

# 권한 설정
chown -R ec2-user:ec2-user /opt/bank-chaos-web

# bank-chaos-web 애플리케이션 설치
echo "Installing bank-chaos-web dependencies..."
cd /opt/bank-chaos-web

if [ -f "package.json" ]; then
    echo "Installing npm dependencies..."
    sudo -u ec2-user npm install || {
        echo "CRITICAL: npm install failed"
        exit 1
    }
    
    echo "✅ bank-chaos-web dependencies installed successfully"
    echo "Ready to run with npm run dev (port 3000)"
else
    echo "ERROR: No package.json found in bank-chaos-web"
    exit 1
fi

# nginx 없이 직접 포트 3000 사용
echo "bank-chaos-web will run directly on port 3000 without nginx proxy"

# PM2 설정 파일 생성 (Development Mode)
echo "Creating PM2 configuration for bank-chaos-web development..."
cat > /opt/bank-chaos-web/ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'bank-chaos-web-dev',
      script: 'npm',
      args: 'run dev',
      cwd: '/opt/bank-chaos-web',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '2G',
      node_args: '--max-old-space-size=2048',
      env: {
        NODE_ENV: 'development',
        PORT: 3000,
        NEXT_TELEMETRY_DISABLED: '1',
        INSTANCE_ID: '$INSTANCE_ID',
        AWS_AVAILABILITY_ZONE: '$AWS_AVAILABILITY_ZONE',
        AWS_REGION: '$AWS_REGION'
      },
      error_file: '/opt/bank-chaos-web/logs/error.log',
      out_file: '/opt/bank-chaos-web/logs/out.log',
      log_file: '/opt/bank-chaos-web/logs/combined.log',
      time: true
    }
  ]
};
EOF

# 로그 디렉토리 생성
mkdir -p /opt/bank-chaos-web/logs
chown -R ec2-user:ec2-user /opt/bank-chaos-web

# 서비스 시작
echo "Starting bank-chaos-web development server..."

# PM2로 bank-chaos-web 개발 서버 시작
echo "Starting bank-chaos-web development server with PM2..."
cd /opt/bank-chaos-web

# PM2 경로 찾기
PM2_PATH=""
for path in "/usr/local/bin/pm2" "/usr/bin/pm2" "$(which pm2 2>/dev/null)" "$(sudo -u ec2-user which pm2 2>/dev/null)" "$(npm root -g)/pm2/bin/pm2"; do
    if [ -f "$path" ] && [ -x "$path" ]; then
        PM2_PATH="$path"
        echo "Found PM2 at: $PM2_PATH"
        break
    fi
done

if [ -n "$PM2_PATH" ]; then
    echo "Starting PM2 bank-chaos-web development server..."
    sudo -u ec2-user bash -c "cd /opt/bank-chaos-web && $PM2_PATH start ecosystem.config.js && $PM2_PATH save"
    
    # PM2 startup 설정
    echo "Setting up PM2 startup..."
    sudo -u ec2-user $PM2_PATH startup systemd -u ec2-user --hp /home/ec2-user
else
    echo "❌ CRITICAL: PM2 not found"
    exit 1
fi

# 헬스체크
echo "Waiting for bank-chaos-web development server to start..."
sleep 60

echo "Running health checks..."
for i in {1..20}; do
    WEB_DEV_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    
    echo "Health check $i/20: DEV_SERVER=$WEB_DEV_STATUS"
    
    if [ "$WEB_DEV_STATUS" = "200" ]; then
        echo "✅ bank-chaos-web development server is responding successfully!"
        break
    fi
    
    if [ $i -eq 20 ]; then
        echo "⚠️  Health checks failed, checking status..."
        echo "PM2 Status:"
        sudo -u ec2-user $PM2_PATH list || echo "PM2 list failed"
        echo "PM2 Logs:"
        sudo -u ec2-user $PM2_PATH logs bank-chaos-web-dev --lines 30 || echo "PM2 logs failed"
        echo "Process Status:"
        ps aux | grep -E "(node|npm|next)" | grep -v grep || echo "No Node.js processes found"
    fi
    
    sleep 30
done

echo "====================================="
echo "bank-chaos-web Development Setup Completed!"
echo "Timestamp: $(date)"
echo "Instance: $INSTANCE_ID ($PRIVATE_IP)"
echo ""
echo "🚀 bank-chaos-web is running in DEVELOPMENT mode"
echo "   - Development Server: http://localhost:3000"
echo "   - Public Access: http://[PUBLIC_IP]:3000"
echo ""
echo "📋 Features:"
echo "   - Hot Reload enabled"
echo "   - Development logging"
echo "   - Source maps enabled"
echo "   - Fast refresh enabled"
echo ""
echo "💡 Debugging Commands:"
echo "   sudo -u ec2-user $PM2_PATH list"
echo "   sudo -u ec2-user $PM2_PATH logs bank-chaos-web-dev"
echo "   sudo -u ec2-user $PM2_PATH restart bank-chaos-web-dev"
echo "   curl http://localhost:3000"
echo ""
echo "📁 Application Path: /opt/bank-chaos-web"
echo "📄 Logs Path: /opt/bank-chaos-web/logs/"
echo "=====================================" 