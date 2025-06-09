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
    dnf install -y nodejs npm || exit 1
    dnf install -y nginx || exit 1
}

# PM2 설치
npm install -g pm2 || exit 1

# 환경 변수 설정
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AWS_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# 애플리케이션 디렉토리 생성
mkdir -p /opt/bank-demo
cd /opt/bank-demo

# GitHub에서 코드 다운로드
echo "Downloading application code..."
for i in {1..3}; do
    rm -rf /opt/bank-demo/* 2>/dev/null || true
    if git clone https://github.com/jeonghun-app/chaos-senario-svc.git .; then
        echo "Repository downloaded successfully"
        break
    fi
    echo "Download attempt $i failed, retrying..."
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

# 애플리케이션 설치
if [ -d "bank-demo-was" ]; then
    echo "Installing WAS application..."
    cd bank-demo-was
    npm install --production
    mkdir -p logs
    cd ..
fi

if [ -d "bank-demo-web" ]; then
    echo "Installing Web application..."
    cd bank-demo-web
    npm install --production
    npm run build || echo "Build failed, continuing..."
    cd ..
fi

# nginx 설정
cat > /etc/nginx/conf.d/bank-demo.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    location /health {
        proxy_pass http://127.0.0.1:8080/api/health;
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
    }
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
    
    location /api/ {
        proxy_pass http://127.0.0.1:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# PM2 설정
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'bank-demo-was',
      script: 'bank-demo-was/server.js',
      cwd: '/opt/bank-demo',
      instances: 1,
      env: {
        NODE_ENV: 'production',
        PORT: 8080,
        INSTANCE_ID: '$INSTANCE_ID',
        AWS_AVAILABILITY_ZONE: '$AWS_AVAILABILITY_ZONE',
        AWS_REGION: '$AWS_REGION'
      }
    },
    {
      name: 'bank-demo-web',
      script: 'npm',
      args: 'start',
      cwd: '/opt/bank-demo/bank-demo-web',
      instances: 1,
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        NEXT_PUBLIC_API_URL: 'http://localhost:8080/api'
      }
    }
  ]
};
EOF

# 권한 설정
chown -R ec2-user:ec2-user /opt/bank-demo

# 서비스 시작
systemctl enable nginx
systemctl start nginx

cd /opt/bank-demo
su - ec2-user -c "cd /opt/bank-demo && pm2 start ecosystem.config.js"
su - ec2-user -c "pm2 save"

# 헬스체크
echo "Waiting for services..."
sleep 30

for i in {1..10}; do
    NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 || echo "000")
    echo "Health check $i/10: NGINX=$NGINX_STATUS"
    
    if [ "$NGINX_STATUS" = "200" ] || [ "$NGINX_STATUS" = "502" ]; then
        echo "Services are responding"
        break
    fi
    sleep 10
done

echo "====================================="
echo "Setup completed at $(date)"
echo "Instance: $INSTANCE_ID ($PRIVATE_IP)"
echo "Services should be available on port 80"
echo "=====================================" 