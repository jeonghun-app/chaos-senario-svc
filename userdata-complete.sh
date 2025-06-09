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

# 메모리 최적화 설정
echo "Optimizing system for build process..."

# 스왑 파일 생성 (메모리가 부족한 경우 대비)
if [ ! -f /swapfile ]; then
    echo "Creating swap file for build process..."
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
        
        # 메모리 사용량 모니터링 함수
        monitor_build() {
            local pid=$1
            while kill -0 $pid 2>/dev/null; do
                echo "Build progress... Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
                sleep 30
            done
        }
        
        # 1차 시도: 가장 가벼운 설정으로 빠른 빌드
        echo "🚀 Attempting lightweight build (3 minutes timeout)..."
        if timeout 180 sudo -u ec2-user bash -c "
            export NODE_OPTIONS='--max-old-space-size=512'
            export NEXT_TELEMETRY_DISABLED=1
            export NODE_ENV=production
            npm run build
        " & monitor_build $!; then
            echo "✅ Lightweight build completed successfully"
        else
            echo "⚠️  Lightweight build failed, trying standard build..."
            
            # 2차 시도: 표준 설정
            echo "🔄 Attempting standard build (5 minutes timeout)..."
            if timeout 300 sudo -u ec2-user bash -c "
                export NODE_OPTIONS='--max-old-space-size=1024'
                export NEXT_TELEMETRY_DISABLED=1
                npm run build
            " & monitor_build $!; then
                echo "✅ Standard build completed successfully"
            else
                echo "⚠️  Standard build failed, trying development mode build..."
                
                # 3차 시도: 개발 모드 빌드
                echo "🛠️  Attempting development build..."
                if timeout 120 sudo -u ec2-user bash -c "
                    export NODE_OPTIONS='--max-old-space-size=512'
                    export NEXT_TELEMETRY_DISABLED=1
                    export NODE_ENV=development
                    npm run build
                " & monitor_build $!; then
                    echo "✅ Development build completed"
                else
                    echo "❌ All build attempts failed. Using production fallback..."
                    
                    # 폴백: 수동으로 필요한 구조 생성
                    echo "Creating minimal Next.js production structure..."
                    sudo -u ec2-user mkdir -p .next/static .next/server/pages .next/server/chunks
                    sudo -u ec2-user echo '"production"' > .next/BUILD_ID
                    sudo -u ec2-user echo '{"version":"15.3.3"}' > .next/required-server-files.json
                    
                    # 기본 페이지 생성
                    sudo -u ec2-user mkdir -p pages
                    sudo -u ec2-user cat > pages/index.js << 'EOFPAGE'
export default function Home() {
  return (
    <div style={{padding: '20px', textAlign: 'center'}}>
      <h1>Bank Demo Application</h1>
      <p>Application is running in fallback mode.</p>
      <p>Please check the build logs and rebuild manually if needed.</p>
    </div>
  )
}
EOFPAGE
                    
                    echo "⚠️  Using fallback mode - manual build may be required later"
                fi
            fi
        fi
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

# PM2 경로 찾기
PM2_PATH=""
for path in "/usr/local/bin/pm2" "/usr/bin/pm2" "$(which pm2 2>/dev/null)" "$(sudo -u ec2-user which pm2 2>/dev/null)" "$(npm root -g)/pm2/bin/pm2"; do
    if [ -f "$path" ] && [ -x "$path" ]; then
        PM2_PATH="$path"
        echo "Found PM2 at: $PM2_PATH"
        break
    fi
done

# PM2를 찾지 못한 경우 다시 설치 시도
if [ -z "$PM2_PATH" ]; then
    echo "PM2 not found, attempting reinstallation..."
    npm install -g pm2 --force
    sleep 5
    
    # 재설치 후 다시 경로 찾기
    for path in "/usr/local/bin/pm2" "/usr/bin/pm2" "$(which pm2 2>/dev/null)" "$(sudo -u ec2-user which pm2 2>/dev/null)" "$(npm root -g)/pm2/bin/pm2"; do
        if [ -f "$path" ] && [ -x "$path" ]; then
            PM2_PATH="$path"
            echo "Found PM2 after reinstall at: $PM2_PATH"
            break
        fi
    done
fi

# PM2 실행
if [ -n "$PM2_PATH" ]; then
    echo "Starting PM2 applications..."
    sudo -u ec2-user bash -c "cd /opt/bank-demo && $PM2_PATH start ecosystem.config.js && $PM2_PATH save"
    
    # PM2 startup 설정 (sudo 권한 필요)
    echo "Setting up PM2 startup..."
    sudo -u ec2-user $PM2_PATH startup systemd -u ec2-user --hp /home/ec2-user
else
    echo "❌ CRITICAL: PM2 not found even after reinstallation"
    echo "Attempting to start applications directly with nohup..."
    
    # PM2 없이 직접 실행 (폴백)
    cd /opt/bank-demo/bank-demo-was
    if [ -f "server.js" ]; then
        sudo -u ec2-user nohup node server.js > /opt/bank-demo/logs/was-direct.log 2>&1 &
        echo "Started WAS directly with nohup"
    fi
    
    cd /opt/bank-demo/bank-demo-web
    if [ -f "package.json" ]; then
        sudo -u ec2-user nohup npm start > /opt/bank-demo/logs/web-direct.log 2>&1 &
        echo "Started Web directly with nohup"
    fi
fi

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
        if [ -n "$PM2_PATH" ]; then
            sudo -u ec2-user $PM2_PATH list || echo "PM2 list failed"
        else
            echo "PM2 not available, checking processes directly:"
            ps aux | grep -E "(node|npm)" | grep -v grep || echo "No Node.js processes found"
        fi
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
if [ -n "$PM2_PATH" ]; then
    echo "  sudo -u ec2-user $PM2_PATH list"
    echo "  sudo -u ec2-user $PM2_PATH logs"
else
    echo "  ps aux | grep node"
    echo "  cat /opt/bank-demo/logs/*.log"
fi
echo "  sudo systemctl status nginx"
echo "  curl http://localhost/health"
echo "=====================================" 