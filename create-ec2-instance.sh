#!/bin/bash

# AWS Bank Demo - EC2 Instance 생성 스크립트
# us-east-1 리전에 EC2 인스턴스를 생성합니다

echo "====================================="
echo "AWS Bank Demo EC2 Instance 생성"
echo "====================================="

# 변수 설정
REGION="us-east-1"
VPC_ID="vpc-00c2db4c26324e6f8"
SUBNET_ID="subnet-0965c00cce99ea63c"
SECURITY_GROUP_ID="sg-0d8ba709de8330b24"
IAM_INSTANCE_PROFILE="arn:aws:iam::081041735764:instance-profile/EC2Sec"
INSTANCE_TYPE="t3.medium"
STORAGE_SIZE="100"
AMI_ID="ami-0340d40dae6a2cbcf"  # Amazon Linux 2023

# UserData 파일 확인 (최신 버전 사용)
USERDATA_FILE="userdata-complete.sh"
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
echo ""

# EC2 인스턴스 생성
echo "EC2 인스턴스 생성 중..."

INSTANCE_ID=$(aws ec2 run-instances \
    --region us-east-1 \
    --image-id ami-0340d40dae6a2cbcf \
    --instance-type t3.medium \
    --subnet-id subnet-0965c00cce99ea63c \
    --security-group-ids sg-0d8ba709de8330b24 \
    --iam-instance-profile Arn=arn:aws:iam::081041735764:instance-profile/EC2Sec \
    --associate-public-ip-address \
    --user-data file://$USERDATA_FILE \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":100,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=BankDemo-WebWAS-Instance},{Key=Project,Value=ChaosEngineering},{Key=Environment,Value=Demo},{Key=ChaosTarget,Value=true}]' \
    --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled' \
    --monitoring 'Enabled=true' \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ $? -eq 0 ] && [ ! -z "$INSTANCE_ID" ]; then
    echo ""
    echo "✅ EC2 인스턴스가 성공적으로 생성되었습니다!"
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
    echo "   2. UserData 스크립트 실행 완료 대기 (약 5-10분)"
    echo "   3. 퍼블릭 IP로 웹 접속 확인"
    echo ""
    echo "🔍 UserData 실행 로그 확인 방법 (SSH 접속 후):"
    echo "   sudo tail -f /var/log/userdata-setup.log"
    echo "   sudo journalctl -u cloud-final -f"
    echo ""
    echo "🌐 서비스 접속 (인스턴스 준비 완료 후):"
    echo "   - 웹 애플리케이션: http://[PUBLIC_IP]"
    echo "   - 헬스체크: http://[PUBLIC_IP]/health"
    echo "   - WAS 직접 접속: http://[PUBLIC_IP]:8080/api/health"
    echo ""
    echo "💡 디버깅 명령어 (SSH 접속 후):"
    echo "   sudo pm2 list                    # PM2 프로세스 상태"
    echo "   sudo systemctl status nginx     # Nginx 상태"
    echo "   sudo systemctl status cloud-*   # Cloud-init 상태"
    
else
    echo "❌ EC2 인스턴스 생성에 실패했습니다."
    echo "AWS CLI 오류를 확인해주세요."
    exit 1
fi 