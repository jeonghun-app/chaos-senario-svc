#!/bin/bash

# AWS Bank Demo - Launch Template UserData Script
# For use with pre-built AMI that already has all software installed

LOG_FILE="/var/log/userdata-startup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "============================================="
echo "AWS Bank Demo Launch Template Startup"
echo "Timestamp: $(date)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "============================================="

# 환경 변수 업데이트
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AWS_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Instance environment:"
echo "  INSTANCE_ID: $INSTANCE_ID"
echo "  AWS_AVAILABILITY_ZONE: $AWS_AVAILABILITY_ZONE"
echo "  AWS_REGION: $AWS_REGION"
echo "  PRIVATE_IP: $PRIVATE_IP"

# 환경 변수 파일 업데이트
cd /opt/bank-demo
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

# PM2 ecosystem 파일에서 환경 변수 업데이트
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
      node_args: '--max-old-space-size=1024',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        NEXT_PUBLIC_API_URL: 'http://localhost:8080/api',
        NEXT_TELEMETRY_DISABLED: '1'
      },
      error_file: '/opt/bank-demo/logs/web-error.log',
      out_file: '/opt/bank-demo/logs/web-out.log',
      log_file: '/opt/bank-demo/logs/web-combined.log'
    }
  ]
};
EOF

# 로그 디렉토리 정리 및 권한 설정
echo "Cleaning up logs and setting permissions..."
rm -f /opt/bank-demo/logs/*.log
mkdir -p /opt/bank-demo/logs
chown -R ec2-user:ec2-user /opt/bank-demo

# Nginx 시작
echo "Starting Nginx..."
systemctl enable nginx
systemctl start nginx

# PM2 기존 프로세스 정리 및 재시작
echo "Starting applications with PM2..."
cd /opt/bank-demo

# PM2 경로 찾기
PM2_PATH=""
for path in "/usr/local/bin/pm2" "/usr/bin/pm2" "$(which pm2 2>/dev/null)" "$(sudo -u ec2-user which pm2 2>/dev/null)"; do
    if [ -f "$path" ] && [ -x "$path" ]; then
        PM2_PATH="$path"
        echo "Found PM2 at: $PM2_PATH"
        break
    fi
done

if [ -z "$PM2_PATH" ]; then
    echo "❌ CRITICAL: PM2 not found in AMI"
    exit 1
fi

# PM2 프로세스 정리
sudo -u ec2-user $PM2_PATH delete all 2>/dev/null || true
sudo -u ec2-user $PM2_PATH kill 2>/dev/null || true

# PM2 시작
sudo -u ec2-user $PM2_PATH start ecosystem.config.js
sudo -u ec2-user $PM2_PATH save
sudo -u ec2-user $PM2_PATH startup systemd -u ec2-user --hp /home/ec2-user

# 서비스 시작 대기
echo "Waiting for services to start..."
sleep 15

# 헬스체크
echo "Running health checks..."
for i in {1..5}; do
    WAS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health 2>/dev/null || echo "000")
    WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
    
    echo "Health check $i/5: WAS=$WAS_STATUS, WEB=$WEB_STATUS, NGINX=$NGINX_STATUS"
    
    if [ "$NGINX_STATUS" = "200" ] || [ "$WAS_STATUS" = "200" ]; then
        echo "✅ Services are responding successfully!"
        break
    fi
    
    if [ $i -eq 5 ]; then
        echo "⚠️  Health checks not fully successful, checking service status..."
        echo "PM2 Status:"
        sudo -u ec2-user $PM2_PATH list || echo "PM2 list failed"
        echo "Nginx Status:"
        systemctl status nginx --no-pager || echo "Nginx status failed"
    fi
    
    sleep 10
done

echo "============================================="
echo "Startup completed at $(date)"
echo "Instance: $INSTANCE_ID ($PRIVATE_IP)"
echo "Services available on port 80"
echo ""
echo "Debug commands:"
echo "  sudo -u ec2-user $PM2_PATH list"
echo "  sudo -u ec2-user $PM2_PATH logs"
echo "  sudo systemctl status nginx"
echo "  curl http://localhost/health"
echo "=============================================" 