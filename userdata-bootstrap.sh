#!/bin/bash

# AWS Bank Demo - Minimal UserData Bootstrap Script
# This script downloads and executes the full setup script from GitHub

LOG_FILE="/var/log/userdata-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "====================================="
echo "AWS Bank Demo Bootstrap Started"
echo "Timestamp: $(date)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "====================================="

# RPM lock 대기 함수 (간소화)
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

# 필수 도구 확인 함수
check_tools() {
    echo "Checking essential tools..."
    
    if ! command -v git >/dev/null 2>&1; then
        echo "git not found - will be installed"
        return 1
    fi
    
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        echo "No download tool found - will install wget"
        return 1
    fi
    
    echo "Essential tools are available"
    return 0
}

# 필수 패키지 설치
install_essentials() {
    wait_for_rpm
    dnf update -y || echo "Update failed, continuing..."
    
    wait_for_rpm
    # curl은 Amazon Linux 2023에 기본 설치되어 있음
    dnf install -y git wget --allowerasing || {
        echo "Trying without curl..."
        dnf install -y git wget || {
            echo "CRITICAL: Failed to install essential packages"
            exit 1
        }
    }
    
    # curl 설치 확인
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl not found, but wget is available for downloads"
    fi
}

# 설정 스크립트 다운로드 및 실행
download_and_run() {
    mkdir -p /opt/bank-demo
    cd /opt/bank-demo
    
    # GitHub에서 전체 설정 스크립트 다운로드
    for i in {1..3}; do
        echo "Cloning repository (attempt $i/3)..."
        
        # 디렉토리 완전 정리
        rm -rf /opt/bank-demo/.git /opt/bank-demo/* /opt/bank-demo/.*  2>/dev/null || true
        
        # git clone 시도
        if git clone https://github.com/jeonghun-app/chaos-senario-svc.git /opt/bank-demo; then
            echo "Repository cloned successfully"
            # 파일 목록 확인
            echo "Repository contents:"
            ls -la /opt/bank-demo/
            
            # setup-complete.sh 확인, 없으면 userdata-script.sh 사용
            if [ -f "/opt/bank-demo/setup-complete.sh" ]; then
                echo "setup-complete.sh found"
                break
            elif [ -f "/opt/bank-demo/userdata-script.sh" ]; then
                echo "Using userdata-script.sh as setup script"
                cp /opt/bank-demo/userdata-script.sh /opt/bank-demo/setup-complete.sh
                chmod +x /opt/bank-demo/setup-complete.sh
                break
            else
                echo "No setup script found in repository"
                # 기본 설정 스크립트 생성
                echo "Creating minimal setup script..."
                cat > /opt/bank-demo/setup-complete.sh << 'EOFSCRIPT'
#!/bin/bash
echo "Minimal setup script running..."
dnf install -y nodejs npm nginx --allowerasing
npm install -g pm2

# GitHub에서 다운로드한 프로젝트가 있는지 확인
if [ -d "bank-demo-was" ] && [ -d "bank-demo-web" ]; then
    echo "Bank demo applications found, installing..."
    cd bank-demo-was && npm install --production && cd ..
    cd bank-demo-web && npm install --production && npm run build && cd ..
    echo "Setup completed with GitHub repository"
else
    echo "No bank demo applications found in repository"
fi
EOFSCRIPT
                chmod +x /opt/bank-demo/setup-complete.sh
                break
            fi
        else
            echo "Git clone failed (attempt $i)"
        fi
        
        if [ $i -lt 3 ]; then
            echo "Retrying in 15 seconds..."
            sleep 15
        fi
    done
    
    # 전체 설정 스크립트 실행
    if [ -f "/opt/bank-demo/setup-complete.sh" ]; then
        chmod +x /opt/bank-demo/setup-complete.sh
        bash /opt/bank-demo/setup-complete.sh
    else
        echo "ERROR: setup-complete.sh not found"
        exit 1
    fi
}

# 실행
if ! check_tools; then
    install_essentials
fi

download_and_run

echo "Bootstrap completed at $(date)" 