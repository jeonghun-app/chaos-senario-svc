#!/bin/bash

# AWS Bank Demo - Complete Setup Script
# This script is executed by the UserData bootstrap after downloading from GitHub

echo "====================================="
echo "Complete Setup Script Started"
echo "Timestamp: $(date)"
echo "Working Directory: $(pwd)"
echo "====================================="

# RPM lock 대기 함수
wait_for_rpm_lock() {
    local max_wait=300
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if ! pgrep -x "dnf\|yum\|rpm" > /dev/null && ! fuser /var/lib/rpm/.rpm.lock > /dev/null 2>&1; then
            return 0
        fi
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    pkill -f "dnf\|yum\|rpm" || true
    rm -f /var/lib/rpm/.rpm.lock /var/cache/dnf/metadata_lock.pid || true
    sleep 5
}

# 추가 패키지 설치
echo "Installing additional packages..."
wait_for_rpm_lock
dnf install -y unzip htop jq nodejs npm --allowerasing || {
    echo "Trying without potential conflicts..."
    dnf install -y unzip htop jq || echo "Some packages failed to install"
    
    # Node.js 별도 설치 시도
    dnf install -y nodejs npm || {
        echo "ERROR: Failed to install Node.js"
        exit 1
    }
}

# PM2 설치
echo "Installing PM2..."
npm install -g pm2 || {
    echo "ERROR: Failed to install PM2"
    exit 1
}

# AWS CLI v2 설치
echo "Installing AWS CLI v2..."
cd /tmp

# curl 또는 wget으로 다운로드
if command -v curl >/dev/null 2>&1; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
else
    wget "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O "awscliv2.zip"
fi

unzip -q awscliv2.zip
./aws/install

# CloudWatch Agent 설치
echo "Installing CloudWatch Agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
wait_for_rpm_lock
rpm -U ./amazon-cloudwatch-agent.rpm || echo "CloudWatch Agent install failed"

# 환경 변수 설정
echo "Setting up environment variables..."
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export AWS_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > /opt/bank-demo/.env << EOF
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
echo "Setting up applications..."
cd /opt/bank-demo

# WAS 설정
if [ -d "bank-demo-was" ] && [ -f "bank-demo-was/package.json" ]; then
    cd bank-demo-was
    npm install --production
    mkdir -p logs
    cd ..
else
    echo "ERROR: bank-demo-was not found"
    exit 1
fi

# Web 설정
if [ -d "bank-demo-web" ] && [ -f "bank-demo-web/package.json" ]; then
    cd bank-demo-web
    npm install --production
    npm run build
    cd ..
else
    echo "ERROR: bank-demo-web not found"
    exit 1
fi

# nginx 설치 및 설정
echo "Installing nginx..."
wait_for_rpm_lock
dnf install -y nginx --allowerasing || {
    echo "Trying nginx installation without conflicts..."
    dnf install -y nginx || {
        echo "ERROR: Failed to install nginx"
        exit 1
    }
}

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
cat > /opt/bank-demo/ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'bank-demo-was',
      script: 'bank-demo-was/server.js',
      cwd: '/opt/bank-demo',
      instances: 'max',
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production',
        PORT: 8080,
        INSTANCE_ID: '$INSTANCE_ID',
        AWS_AVAILABILITY_ZONE: '$AWS_AVAILABILITY_ZONE',
        AWS_REGION: '$AWS_REGION',
        PRIVATE_IP: '$PRIVATE_IP',
        CLOUDWATCH_ENABLED: 'true',
        LOG_LEVEL: 'info'
      },
      log_file: 'logs/combined.log',
      out_file: 'logs/out.log',
      error_file: 'logs/error.log'
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
        NEXT_PUBLIC_API_URL: 'http://localhost:8080/api',
        INSTANCE_ID: '$INSTANCE_ID',
        AWS_AVAILABILITY_ZONE: '$AWS_AVAILABILITY_ZONE',
        PRIVATE_IP: '$PRIVATE_IP'
      }
    }
  ]
};
EOF

# CloudWatch Agent 설정
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "ec2-user"
  },
  "metrics": {
    "namespace": "BankDemo/EC2",
    "metrics_collected": {
      "cpu": {"measurement": ["cpu_usage_idle", "cpu_usage_user"], "metrics_collection_interval": 60},
      "mem": {"measurement": ["mem_used_percent"], "metrics_collection_interval": 60}
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/bank-demo/logs/*.log",
            "log_group_name": "/aws/ec2/bank-demo",
            "log_stream_name": "{instance_id}/application"
          }
        ]
      }
    }
  }
}
EOF

# 권한 설정
chown -R ec2-user:ec2-user /opt/bank-demo

# 서비스 시작
echo "Starting services..."
systemctl enable nginx
systemctl start nginx

cd /opt/bank-demo
su - ec2-user -c "cd /opt/bank-demo && pm2 start ecosystem.config.js"
su - ec2-user -c "pm2 save"

# CloudWatch Agent 시작
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 헬스체크 대기
echo "Waiting for services to start..."
sleep 45

for i in {1..12}; do
    WAS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health)
    WEB_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
    NGINX_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health)
    
    if [ "$WAS_CHECK" = "200" ] && [ "$WEB_CHECK" = "200" ] && [ "$NGINX_CHECK" = "200" ]; then
        echo "All services are ready!"
        break
    fi
    
    echo "Attempt $i/12: WAS=$WAS_CHECK, WEB=$WEB_CHECK, NGINX=$NGINX_CHECK"
    sleep 5
done

echo "====================================="
echo "Setup Completed Successfully"
echo "Timestamp: $(date)"
echo "Instance ID: $INSTANCE_ID"
echo "Services: WAS($WAS_CHECK) WEB($WEB_CHECK) NGINX($NGINX_CHECK)"
echo "=====================================" 