#!/bin/bash

# AWS Bank Demo - Complete UserData Script
# This single script handles everything without external dependencies

LOG_FILE="/var/log/userdata-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "====================================="
echo "AWS Bank Demo Complete Setup Started"
echo "Timestamp: $(date)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "====================================="

# 오류 발생시 즉시 종료
set -e

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
dnf install -y git wget unzip htop jq nodejs npm nginx --allowerasing || {
    echo "Some packages failed, trying individually..."
    dnf install -y nodejs npm || {
        echo "CRITICAL: Failed to install Node.js/npm"
        exit 1
    }
    dnf install -y nginx || {
        echo "CRITICAL: Failed to install nginx"
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
mkdir -p /opt/bank-demo
cd /opt/bank-demo

# GitHub에서 코드 다운로드 (수정된 URL)
echo "Downloading application code..."
for i in {1..3}; do
    rm -rf /opt/bank-demo/* 2>/dev/null || true
    echo "Download attempt $i/3..."
    if git clone https://github.com/jeonghun-app/chaos-senario-svc.git /tmp/repo && cp -r /tmp/repo/* /opt/bank-demo/; then
        echo "Repository downloaded successfully"
        rm -rf /tmp/repo
        break
    elif [ $i -eq 3 ]; then
        echo "CRITICAL: Failed to download repository after 3 attempts"
        echo "Fallback: Using local directory structure..."
        mkdir -p bank-demo-was bank-demo-web
        echo "Created minimal directory structure"
    fi
    sleep 10
done

# 환경 변수 파일 생성
cat > .env << EOF
INSTANCE_ID=$INSTANCE_ID
AWS_AVAILABILITY_ZONE=$AWS_AVAILABILITY_ZONE
AWS_REGION=$AWS_REGION
PRIVATE_IP=$PRIVATE_IP
NODE_ENV=production
WAS_PORT=8080
WEB_PORT=3000
NEXT_PUBLIC_API_URL=http://localhost:8080/api
CLOUDWATCH_ENABLED=true
LOG_LEVEL=info
EOF

# 권한 설정 (먼저 설정)
chown -R ec2-user:ec2-user /opt/bank-demo

# 애플리케이션 설치
if [ -d "bank-demo-was" ]; then
    echo "Installing WAS application..."
    cd bank-demo-was
    if [ -f "package.json" ]; then
        sudo -u ec2-user npm install || {
            echo "CRITICAL: WAS npm install failed"
            exit 1
        }
        mkdir -p logs
        chown -R ec2-user:ec2-user logs
    else
        echo "WARNING: No package.json found in bank-demo-was"
    fi
    cd ..
else
    echo "WARNING: bank-demo-was directory not found"
fi

if [ -d "bank-demo-web" ]; then
    echo "Installing Web application..."
    cd bank-demo-web
    if [ -f "package.json" ]; then
        sudo -u ec2-user npm install || {
            echo "CRITICAL: Web npm install failed"
            exit 1
        }
        
        # PostCSS 관련 패키지 명시적 설치 (빌드 에러 방지)
        echo "Installing PostCSS dependencies..."
        sudo -u ec2-user npm install @tailwindcss/postcss tailwindcss --save-dev || {
            echo "WARNING: PostCSS packages installation failed, trying to continue..."
        }
        
        echo "Building Next.js application..."
        sudo -u ec2-user npm run build || {
            echo "CRITICAL: Next.js build failed"
            exit 1
        }
    else
        echo "WARNING: No package.json found in bank-demo-web"
    fi
    cd ..
else
    echo "WARNING: bank-demo-web directory not found"
fi

# nginx 설정
echo "Configuring nginx..."
cat > /etc/nginx/conf.d/bank-demo.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8080/api/health;
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    # API endpoints
    location /api/ {
        proxy_pass http://127.0.0.1:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # Main web application
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# PM2 설정 파일 생성
echo "Creating PM2 configuration..."
cat > /opt/bank-demo/ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'bank-demo-was',
      script: 'server.js',
      cwd: '/opt/bank-demo/bank-demo-was',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 8080,
        INSTANCE_ID: '$INSTANCE_ID',
        AWS_AVAILABILITY_ZONE: '$AWS_AVAILABILITY_ZONE',
        AWS_REGION: '$AWS_REGION'
      },
      error_file: '/opt/bank-demo/logs/was-error.log',
      out_file: '/opt/bank-demo/logs/was-out.log',
      log_file: '/opt/bank-demo/logs/was-combined.log'
    },
    {
      name: 'bank-demo-web',
      script: 'npm',
      args: 'start',
      cwd: '/opt/bank-demo/bank-demo-web',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        NEXT_PUBLIC_API_URL: 'http://localhost:8080/api'
      },
      error_file: '/opt/bank-demo/logs/web-error.log',
      out_file: '/opt/bank-demo/logs/web-out.log',
      log_file: '/opt/bank-demo/logs/web-combined.log'
    }
  ]
};
EOF

# 로그 디렉토리 생성
mkdir -p /opt/bank-demo/logs
chown -R ec2-user:ec2-user /opt/bank-demo

# 서비스 시작
echo "Starting services..."

# Nginx 시작
systemctl enable nginx
systemctl start nginx
systemctl status nginx --no-pager

# PM2로 애플리케이션 시작 (ec2-user 권한으로)
echo "Starting applications with PM2..."
cd /opt/bank-demo
sudo -u ec2-user bash -c "cd /opt/bank-demo && /usr/local/bin/pm2 start ecosystem.config.js && /usr/local/bin/pm2 save && /usr/local/bin/pm2 startup"

# 헬스체크
echo "Waiting for services to start..."
sleep 30

echo "Running health checks..."
for i in {1..10}; do
    WAS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health 2>/dev/null || echo "000")
    WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
    
    echo "Health check $i/10: WAS=$WAS_STATUS, WEB=$WEB_STATUS, NGINX=$NGINX_STATUS"
    
    if [ "$NGINX_STATUS" = "200" ] || [ "$WAS_STATUS" = "200" ]; then
        echo "✅ Services are responding successfully!"
        break
    fi
    
    if [ $i -eq 10 ]; then
        echo "⚠️  Health checks failed, but continuing..."
        echo "Service status:"
        sudo -u ec2-user /usr/local/bin/pm2 list || echo "PM2 list failed"
        systemctl status nginx --no-pager || echo "Nginx status failed"
    fi
    
    sleep 10
done

echo "====================================="
echo "Setup completed at $(date)"
echo "Instance: $INSTANCE_ID ($PRIVATE_IP)"
echo "Services should be available on port 80"
echo ""
echo "Debug commands:"
echo "  sudo -u ec2-user /usr/local/bin/pm2 list"
echo "  sudo systemctl status nginx"
echo "  curl http://localhost/health"
echo "=====================================" 