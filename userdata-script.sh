#!/bin/bash

# AWS Chaos Engineering Demo - Bank Web/WAS UserData Script
# 이 스크립트는 EC2 인스턴스가 시작될 때 자동으로 실행되어
# 웹과 WAS 애플리케이션을 설치하고 실행합니다.

LOG_FILE="/var/log/userdata-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "====================================="
echo "AWS Bank Demo UserData Script Started"
echo "Timestamp: $(date)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "====================================="

# 시스템 업데이트
echo "Updating system packages..."
yum update -y

# 필수 패키지 설치
echo "Installing essential packages..."
yum install -y git wget curl unzip htop

# Node.js 18 설치
echo "Installing Node.js 18..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# PM2 글로벌 설치 (프로세스 관리자)
echo "Installing PM2..."
npm install -g pm2

# AWS CLI v2 설치
echo "Installing AWS CLI v2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# CloudWatch Agent 설치
echo "Installing CloudWatch Agent..."
cd /tmp
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# 애플리케이션 디렉토리 생성
echo "Creating application directories..."
mkdir -p /opt/bank-demo
cd /opt/bank-demo

# Git 저장소 클론 (실제 환경에서는 S3나 CodeCommit 사용 권장)
echo "Cloning application code..."
# git clone https://github.com/your-repo/bank-demo.git .
# 여기서는 로컬 파일을 복사하는 것으로 가정
# 실제로는 S3에서 다운로드하거나 CodeDeploy 사용

# 환경 변수 설정
echo "Setting up environment variables..."
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export AWS_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export NODE_ENV=production
export PORT=8080
export FRONTEND_URL="http://localhost:3000"
export CLOUDWATCH_ENABLED=true

# 환경 변수를 파일로 저장
cat > /opt/bank-demo/.env << EOF
INSTANCE_ID=$INSTANCE_ID
AWS_AVAILABILITY_ZONE=$AWS_AVAILABILITY_ZONE
AWS_REGION=$AWS_REGION
NODE_ENV=production
PORT=8080
FRONTEND_URL=http://localhost:3000
CLOUDWATCH_ENABLED=true
LOG_LEVEL=info
EOF

# WAS 애플리케이션 설정 (여기서는 코드가 이미 있다고 가정)
echo "Setting up WAS application..."
cd /opt/bank-demo/bank-demo-was

# package.json이 있다면 의존성 설치
if [ -f "package.json" ]; then
    echo "Installing WAS dependencies..."
    npm install --production
else
    echo "Creating WAS application from scratch..."
    npm init -y
    npm install express cors helmet compression morgan uuid joi winston express-rate-limit aws-sdk
fi

# logs 디렉토리 생성
mkdir -p logs

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
        INSTANCE_ID: process.env.INSTANCE_ID || '$INSTANCE_ID',
        AWS_AVAILABILITY_ZONE: process.env.AWS_AVAILABILITY_ZONE || '$AWS_AVAILABILITY_ZONE',
        AWS_REGION: process.env.AWS_REGION || '$AWS_REGION',
        CLOUDWATCH_ENABLED: 'true'
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
        AWS_AVAILABILITY_ZONE: '$AWS_AVAILABILITY_ZONE'
      },
      log_file: 'logs/web-combined.log',
      out_file: 'logs/web-out.log',
      error_file: 'logs/web-error.log'
    }
  ]
};
EOF

# 웹 애플리케이션 설정
echo "Setting up Web application..."
cd /opt/bank-demo/bank-demo-web

# Next.js 빌드 (이미 빌드된 경우 스킵)
if [ -f "package.json" ] && [ ! -d ".next" ]; then
    echo "Installing Web dependencies and building..."
    npm install --production
    npm run build
fi

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

if [ "$WAS_HEALTH" = "200" ] && [ "$WEB_HEALTH" = "200" ]; then
    echo "$(date): Applications are healthy"
    exit 0
else
    echo "$(date): Applications are unhealthy - WAS: $WAS_HEALTH, WEB: $WEB_HEALTH"
    # 애플리케이션 재시작 시도
    pm2 restart all
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
sleep 30

WAS_STATUS=$(curl -s http://localhost:8080/api/health | jq -r '.status' 2>/dev/null || echo "error")
WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)

echo "====================================="
echo "Bank Demo Setup Completed"
echo "Timestamp: $(date)"
echo "WAS Status: $WAS_STATUS"
echo "Web Status: $WEB_STATUS"
echo "PM2 Processes:"
su - ec2-user -c "pm2 list"
echo "====================================="

# AWS Systems Manager Parameter Store에 상태 업데이트 (선택사항)
aws ssm put-parameter \
    --name "/bank-demo/instance/$INSTANCE_ID/status" \
    --value "ready" \
    --type "String" \
    --overwrite \
    --region "$AWS_REGION" || echo "Failed to update SSM parameter"

echo "UserData script execution completed successfully!" 