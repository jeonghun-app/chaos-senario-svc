#!/bin/bash

# AMI 생성 전 인스턴스 정리 스크립트
# 이 스크립트를 실행한 후 인스턴스를 중지하고 AMI를 생성하세요

echo "==========================================="
echo "Preparing instance for AMI creation..."
echo "Timestamp: $(date)"
echo "==========================================="

# PM2 프로세스 정리
echo "Stopping PM2 processes..."
sudo -u ec2-user /usr/local/bin/pm2 delete all 2>/dev/null || true
sudo -u ec2-user /usr/local/bin/pm2 kill 2>/dev/null || true

# Nginx 정지
echo "Stopping Nginx..."
systemctl stop nginx

# 로그 파일 정리
echo "Cleaning up log files..."
rm -f /var/log/userdata-*.log
rm -f /opt/bank-demo/logs/*.log
rm -rf /home/ec2-user/.pm2/logs/*

# 임시 파일 정리
echo "Cleaning up temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# SSH 키 정리 (보안상 중요)
echo "Cleaning up SSH keys..."
rm -f /home/ec2-user/.ssh/authorized_keys.bak
rm -f /root/.ssh/authorized_keys*

# 인스턴스별 환경 변수 파일 제거
echo "Removing instance-specific environment files..."
rm -f /opt/bank-demo/.env

# PM2 설정에서 인스턴스별 정보 제거
echo "Cleaning PM2 configuration..."
cat > /opt/bank-demo/ecosystem.config.js << 'EOF'
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
        PORT: 8080
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

# 네트워크 관련 정리
echo "Cleaning up network configurations..."
rm -f /etc/udev/rules.d/70-persistent-net.rules

# 시스템 히스토리 정리
echo "Cleaning up command history..."
history -c
rm -f /home/ec2-user/.bash_history
rm -f /root/.bash_history

# 패키지 캐시 정리
echo "Cleaning up package cache..."
dnf clean all

# 권한 재설정
echo "Resetting permissions..."
chown -R ec2-user:ec2-user /opt/bank-demo

echo "==========================================="
echo "AMI preparation completed!"
echo ""
echo "Next steps:"
echo "1. Stop this instance"
echo "2. Create AMI from this instance"
echo "3. Use the new AMI with Launch Template"
echo "4. Use userdata-launchtemplate.sh for the Launch Template"
echo "===========================================" 