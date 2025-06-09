#!/bin/bash

# AWS Bank Demo - bank-chaos-web 전용 EC2 Instance 생성 스크립트
# us-east-1 리전에 bank-chaos-web 개발 서버를 위한 EC2 인스턴스를 생성합니다

echo "====================================="
echo "Bank Chaos Web Development Instance 생성"
echo "====================================="

# 변수 설정
REGION="us-east-1"
VPC_ID="vpc-00c2db4c26324e6f8"
SUBNET_ID="subnet-0ec259c23b31fb8a9"
SECURITY_GROUP_ID="sg-0d8ba709de8330b24"
IAM_INSTANCE_PROFILE="arn:aws:iam::081041735764:instance-profile/EC2Sec"
INSTANCE_TYPE="c5.xlarge"
STORAGE_SIZE="100"
AMI_ID="ami-0340d40dae6a2cbcf"  # Amazon Linux 2023

# UserData 파일 확인 (bank-chaos-web 개발 모드 버전 사용)
USERDATA_FILE="userdata-chaos-web-dev.sh"
if [ ! -f "$USERDATA_FILE" ]; then
    echo "ERROR: $USERDATA_FILE 파일을 찾을 수 없습니다"
    echo "사용 가능한 UserData 파일:"
    ls -la userdata*.sh 2>/dev/null || echo "UserData 파일이 없습니다"
    exit 1
fi

# UserData 크기 확인 (16KB 제한)
USERDATA_SIZE=$(wc -c < "$USERDATA_FILE")
echo "UserData 파일 크기: $USERDATA_SIZE bytes"
if [ $USERDATA_SIZE -gt 16384 ]; then
    echo "WARNING: UserData 파일이 16KB를 초과합니다. AWS 제한을 확인하세요."
fi

echo "설정 정보:"
echo "  리전: $REGION"
echo "  VPC: $VPC_ID"
echo "  서브넷: $SUBNET_ID"
echo "  보안그룹: $SECURITY_GROUP_ID"
echo "  IAM Profile: $IAM_INSTANCE_PROFILE"
echo "  인스턴스 타입: $INSTANCE_TYPE"
echo "  스토리지: ${STORAGE_SIZE}GB"
echo "  AMI: $AMI_ID"
echo "  UserData: $USERDATA_FILE ($USERDATA_SIZE bytes)"
echo "  용도: bank-chaos-web Development Server (npm run dev, port 3000)"
echo ""

# EC2 인스턴스 생성
echo "bank-chaos-web 개발 서버 인스턴스 생성 중..."

INSTANCE_ID=$(aws ec2 run-instances \
    --region us-east-1 \
    --image-id ami-0340d40dae6a2cbcf \
    --instance-type c5.xlarge \
    --subnet-id subnet-0ec259c23b31fb8a9 \
    --security-group-ids sg-0d8ba709de8330b24 \
    --iam-instance-profile Arn=arn:aws:iam::081041735764:instance-profile/EC2Sec \
    --associate-public-ip-address \
    --user-data file://$USERDATA_FILE \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":100,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=BankDemo-ChaosWeb-DevServer},{Key=Project,Value=ChaosEngineering},{Key=Environment,Value=Development},{Key=ChaosTarget,Value=true},{Key=Application,Value=bank-chaos-web},{Key=Mode,Value=npm-run-dev}]' \
    --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled' \
    --monitoring 'Enabled=true' \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ $? -eq 0 ] && [ ! -z "$INSTANCE_ID" ]; then
    echo ""
    echo "✅ bank-chaos-web 개발 서버 인스턴스가 성공적으로 생성되었습니다!"
    echo "   인스턴스 ID: $INSTANCE_ID"
    echo ""
    
    # 인스턴스 상태 확인
    echo "인스턴스 상태 확인 중..."
    aws ec2 describe-instances \
        --region $REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output table
    
    echo ""
    echo "📋 다음 단계:"
    echo "   1. 인스턴스가 완전히 시작될 때까지 대기 (약 3-5분)"
    echo "   2. UserData 스크립트 실행 완료 대기 (약 10-15분)"
    echo "   3. npm dependencies 설치 완료 대기"
    echo "   4. Next.js 개발 서버 시작 확인"
    echo "   5. 퍼블릭 IP로 웹 접속 확인"
    echo ""
    echo "🔍 설치 진행 상황 확인 방법 (SSH 접속 후):"
    echo "   sudo tail -f /var/log/userdata-setup.log"
    echo "   sudo journalctl -u cloud-final -f"
    echo ""
    echo "🌐 서비스 접속 (인스턴스 준비 완료 후):"
    echo "   - bank-chaos-web 개발 서버: http://[PUBLIC_IP]:3000"
    echo ""
    echo "💡 개발 서버 관리 명령어 (SSH 접속 후):"
    echo "   sudo -u ec2-user pm2 list                      # PM2 프로세스 상태"
    echo "   sudo -u ec2-user pm2 logs bank-chaos-web-dev   # 개발 서버 로그"
    echo "   sudo -u ec2-user pm2 restart bank-chaos-web-dev # 개발 서버 재시작"
    echo "   cd /opt/bank-chaos-web && sudo -u ec2-user npm run dev # 수동 실행"
    echo ""
    echo "🔧 개발 관련 정보:"
    echo "   - Hot Reload: 활성화됨"
    echo "   - 포트: 3000 (개발 서버)"
    echo "   - 환경: Development"
    echo "   - nginx: 사용 안함 (직접 접속)"
    echo "   - 애플리케이션 경로: /opt/bank-chaos-web"
    echo "   - 로그 경로: /opt/bank-chaos-web/logs/"
    echo ""
    echo "⚠️  참고사항:"
    echo "   - 개발 서버는 코드 변경 시 자동으로 재시작됩니다"
    echo "   - 파일 수정은 /opt/bank-chaos-web 디렉토리에서 하세요"
    echo "   - PM2를 통해 프로세스가 관리됩니다"
    
else
    echo "❌ bank-chaos-web 개발 서버 인스턴스 생성에 실패했습니다."
    echo "AWS CLI 오류를 확인해주세요."
    exit 1
fi 