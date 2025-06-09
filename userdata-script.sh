#!/bin/bash

# AWS Chaos Engineering Demo - Bank Web/WAS UserData Script
# Amazon Linux 2023 기준으로 EC2 인스턴스 Auto Scaling 환경에서
# 웹과 WAS 애플리케이션을 설치하고 실행합니다.

LOG_FILE="/var/log/userdata-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "====================================="
echo "AWS Bank Demo UserData Script Started"
echo "Timestamp: $(date)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "Region: $(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "====================================="

# RPM lock 대기 함수
wait_for_rpm_lock() {
    local max_wait=300  # 5분 대기
    local wait_time=0
    
    echo "Checking for existing package manager processes..."
    while [ $wait_time -lt $max_wait ]; do
        if ! pgrep -x "dnf\|yum\|rpm" > /dev/null && ! fuser /var/lib/rpm/.rpm.lock > /dev/null 2>&1; then
            echo "Package manager is available."
            return 0
        fi
        
        echo "Package manager is busy. Waiting... ($wait_time/$max_wait seconds)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    echo "Timeout waiting for package manager. Forcing unlock..."
    pkill -f "dnf\|yum\|rpm" || true
    rm -f /var/lib/rpm/.rpm.lock /var/cache/dnf/metadata_lock.pid || true
    sleep 5
}

# 패키지 매니저 대기
wait_for_rpm_lock

# 시스템 업데이트 (Amazon Linux 2023은 dnf 사용)
echo "Updating system packages..."
dnf update -y || {
    echo "System update failed, but continuing..."
}

# 필수 패키지 설치 (재시도 로직 포함)
install_packages() {
    local packages="git wget curl unzip htop jq"
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        echo "Installing essential packages (attempt $((retry_count + 1))/$max_retries)..."
        
        wait_for_rpm_lock
        
        if dnf install -y $packages; then
            echo "Packages installed successfully."
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Package installation failed. Retrying in 30 seconds..."
            sleep 30
        fi
    done
    
    echo "Failed to install packages after $max_retries attempts."
    return 1
}

install_packages || {
    echo "CRITICAL: Failed to install essential packages. Continuing anyway..."
}

# Node.js 18 설치 (Amazon Linux 2023 방식)
install_nodejs() {
    echo "Installing Node.js 18..."
    wait_for_rpm_lock
    
    if dnf install -y nodejs npm; then
        echo "Node.js installed successfully."
        
        # Node.js 버전 확인
        node_version=$(node --version 2>/dev/null || echo "unknown")
        npm_version=$(npm --version 2>/dev/null || echo "unknown")
        echo "Node.js version: $node_version"
        echo "npm version: $npm_version"
        
        return 0
    else
        echo "Failed to install Node.js"
        return 1
    fi
}

install_nodejs || {
    echo "CRITICAL: Failed to install Node.js. Exiting..."
    exit 1
}

# PM2 글로벌 설치 (프로세스 관리자)
install_pm2() {
    echo "Installing PM2..."
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        if npm install -g pm2; then
            echo "PM2 installed successfully."
            pm2 --version
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "PM2 installation failed. Retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    echo "Failed to install PM2 after $max_retries attempts."
    return 1
}

install_pm2 || {
    echo "CRITICAL: Failed to install PM2. Exiting..."
    exit 1
}

# AWS CLI v2 설치
echo "Installing AWS CLI v2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# CloudWatch Agent 설치
install_cloudwatch_agent() {
    echo "Installing CloudWatch Agent..."
    cd /tmp
    
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        echo "Downloading CloudWatch Agent (attempt $((retry_count + 1))/$max_retries)..."
        
        if wget -O amazon-cloudwatch-agent.rpm https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm; then
            echo "CloudWatch Agent downloaded successfully."
            
            wait_for_rpm_lock
            
            if rpm -U ./amazon-cloudwatch-agent.rpm; then
                echo "CloudWatch Agent installed successfully."
                return 0
            else
                echo "Failed to install CloudWatch Agent RPM."
            fi
        else
            echo "Failed to download CloudWatch Agent."
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "CloudWatch Agent installation failed. Retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    echo "Failed to install CloudWatch Agent after $max_retries attempts."
    return 1
}

install_cloudwatch_agent || {
    echo "WARNING: Failed to install CloudWatch Agent. Continuing without it..."
}

# 애플리케이션 디렉토리 생성
echo "Creating application directories..."
mkdir -p /opt/bank-demo
cd /opt/bank-demo

# Git 저장소 클론 (GitHub에서 소스코드 다운로드)
clone_repository() {
    echo "Cloning application code from GitHub..."
    local retry_count=0
    local max_retries=3
    
    # git 명령어 확인
    if ! command -v git > /dev/null 2>&1; then
        echo "ERROR: git command not found. Installing git..."
        wait_for_rpm_lock
        dnf install -y git || {
            echo "CRITICAL: Failed to install git. Exiting..."
            exit 1
        }
    fi
    
    while [ $retry_count -lt $max_retries ]; do
        echo "Cloning repository (attempt $((retry_count + 1))/$max_retries)..."
        
        # 기존 디렉토리 정리
        rm -rf /opt/bank-demo/*
        
        if git clone https://github.com/jeonghun-app/chaos-senario-svc.git /opt/bank-demo; then
            echo "Repository cloned successfully."
            
            # 실행 권한 설정
            chmod +x /opt/bank-demo/userdata-script.sh
            
            # 파일 구조 확인
            echo "Repository contents:"
            ls -la /opt/bank-demo/
            
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Git clone failed. Retrying in 15 seconds..."
            sleep 15
        fi
    done
    
    echo "Failed to clone repository after $max_retries attempts."
    return 1
}

clone_repository || {
    echo "CRITICAL: Failed to clone repository. Exiting..."
    exit 1
}

# 환경 변수 설정
echo "Setting up environment variables..."
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export AWS_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
export NODE_ENV=production
export WAS_PORT=8080
export WEB_PORT=3000
export CLOUDWATCH_ENABLED=true

# 환경 변수를 파일로 저장
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

# WAS 애플리케이션 설정
echo "Setting up WAS application..."
cd /opt/bank-demo/bank-demo-was

if [ -f "package.json" ]; then
    echo "Installing WAS dependencies..."
    npm install --production
    mkdir -p logs
else
    echo "ERROR: WAS package.json not found!"
    exit 1
fi

# Web 애플리케이션 설정
echo "Setting up Web application..."
cd /opt/bank-demo/bank-demo-web

if [ -f "package.json" ]; then
    echo "Installing Web dependencies..."
    npm install --production
    echo "Building Next.js application..."
    npm run build
else
    echo "ERROR: Web package.json not found!"
    exit 1
fi

# PM2 ecosystem 파일 생성
echo "Creating PM2 ecosystem configuration..."
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
      error_file: 'logs/error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      max_memory_restart: '1G',
      node_args: '--max-old-space-size=1024'
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
      },
      log_file: 'logs/web-combined.log',
      out_file: 'logs/web-out.log',
      error_file: 'logs/web-error.log'
    }
  ]
};
EOF

# ALB 헬스체크를 위한 nginx 설정
install_nginx() {
    echo "Installing and configuring nginx for ALB health checks..."
    wait_for_rpm_lock
    
    if dnf install -y nginx; then
        echo "Nginx installed successfully."
        return 0
    else
        echo "Failed to install nginx."
        return 1
    fi
}

install_nginx || {
    echo "CRITICAL: Failed to install nginx. Exiting..."
    exit 1
}

# nginx 설정 파일 생성 (ALB 헬스체크용)
cat > /etc/nginx/conf.d/bank-demo.conf << 'EOF'
# ALB Health Check 전용 설정
server {
    listen 80;
    server_name _;

    # ALB 헬스체크 엔드포인트
    location /health {
        proxy_pass http://127.0.0.1:8080/api/health;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 헬스체크 전용 타임아웃
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
    }

    # 웹 애플리케이션 프록시
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # API 요청 프록시
    location /api/ {
        proxy_pass http://127.0.0.1:8080/api/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# nginx 시작 및 자동 시작 설정
systemctl enable nginx
systemctl start nginx

# systemd 서비스 파일 생성 (PM2 대신 사용 가능)
echo "Creating systemd service..."
cat > /etc/systemd/system/bank-demo.service << EOF
[Unit]
Description=Bank Demo Application
After=network.target

[Service]
Type=forking
User=ec2-user
WorkingDirectory=/opt/bank-demo
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production
ExecStart=/usr/local/bin/pm2 start ecosystem.config.js --no-daemon
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 권한 설정
echo "Setting up permissions..."
chown -R ec2-user:ec2-user /opt/bank-demo
chmod +x /opt/bank-demo/bank-demo-was/server.js

# CloudWatch Agent 설정
echo "Configuring CloudWatch Agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "ec2-user"
  },
  "metrics": {
    "namespace": "BankDemo/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          "io_time"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/bank-demo/logs/*.log",
            "log_group_name": "/aws/ec2/bank-demo",
            "log_stream_name": "{instance_id}/application",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/userdata-setup.log",
            "log_group_name": "/aws/ec2/bank-demo",
            "log_stream_name": "{instance_id}/userdata",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# CloudWatch Agent 시작
echo "Starting CloudWatch Agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 애플리케이션 시작
echo "Starting applications with PM2..."
cd /opt/bank-demo
su - ec2-user -c "cd /opt/bank-demo && pm2 start ecosystem.config.js"
su - ec2-user -c "pm2 save"
su - ec2-user -c "pm2 startup systemd -u ec2-user --hp /home/ec2-user"

# systemd 서비스 활성화
systemctl daemon-reload
systemctl enable bank-demo.service
systemctl start bank-demo.service

# 헬스체크 스크립트 생성
echo "Creating health check script..."
cat > /opt/bank-demo/health-check.sh << 'EOF'
#!/bin/bash
# 애플리케이션 헬스체크 스크립트

WAS_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health)
WEB_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
NGINX_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health)

if [ "$WAS_HEALTH" = "200" ] && [ "$WEB_HEALTH" = "200" ] && [ "$NGINX_HEALTH" = "200" ]; then
    echo "$(date): All services are healthy - WAS: $WAS_HEALTH, WEB: $WEB_HEALTH, NGINX: $NGINX_HEALTH"
    exit 0
else
    echo "$(date): Services are unhealthy - WAS: $WAS_HEALTH, WEB: $WEB_HEALTH, NGINX: $NGINX_HEALTH"
    
    # 서비스별 재시작 시도
    if [ "$WAS_HEALTH" != "200" ] || [ "$WEB_HEALTH" != "200" ]; then
        echo "Restarting PM2 applications..."
        pm2 restart all
    fi
    
    if [ "$NGINX_HEALTH" != "200" ]; then
        echo "Restarting nginx..."
        systemctl restart nginx
    fi
    
    exit 1
fi
EOF

chmod +x /opt/bank-demo/health-check.sh

# 크론 작업 설정 (5분마다 헬스체크)
echo "Setting up health check cron job..."
echo "*/5 * * * * /opt/bank-demo/health-check.sh >> /var/log/health-check.log 2>&1" | crontab -u ec2-user -

# 방화벽 설정 (필요한 경우)
echo "Configuring firewall..."
# Amazon Linux의 기본 방화벽 설정은 보통 비활성화되어 있음
# 필요시 iptables 규칙 추가

# 최종 상태 확인
echo "Performing final health checks..."
sleep 45

# 서비스들이 완전히 시작될 때까지 대기
echo "Waiting for services to fully start..."
for i in {1..12}; do
    WAS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health)
    WEB_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
    
    if [ "$WAS_CHECK" = "200" ] && [ "$WEB_CHECK" = "200" ]; then
        echo "Services are ready!"
        break
    fi
    
    echo "Attempt $i/12: WAS=$WAS_CHECK, WEB=$WEB_CHECK - waiting 5 seconds..."
    sleep 5
done

WAS_STATUS=$(curl -s http://localhost:8080/api/health | jq -r '.status' 2>/dev/null || echo "error")
WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health)
ALB_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health)

echo "====================================="
echo "Bank Demo Setup Completed"
echo "Timestamp: $(date)"
echo "Instance ID: $INSTANCE_ID"
echo "Private IP: $PRIVATE_IP"
echo "Availability Zone: $AWS_AVAILABILITY_ZONE"
echo "---"
echo "Service Status:"
echo "  WAS (8080): $WAS_STATUS"
echo "  WEB (3000): $WEB_STATUS" 
echo "  NGINX (80): $NGINX_STATUS"
echo "  ALB Health: $ALB_HEALTH"
echo "---"
echo "PM2 Processes:"
su - ec2-user -c "pm2 list"
echo "---"
echo "Nginx Status:"
systemctl status nginx --no-pager -l
echo "====================================="

# AWS Systems Manager Parameter Store에 상태 업데이트 (선택사항)
aws ssm put-parameter \
    --name "/bank-demo/instance/$INSTANCE_ID/status" \
    --value "ready" \
    --type "String" \
    --overwrite \
    --region "$AWS_REGION" || echo "Failed to update SSM parameter"

echo "UserData script execution completed successfully!" 