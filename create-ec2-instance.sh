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

# UserData Base64 인코딩 파일 확인
if [ ! -f "userdata-base64.txt" ]; then
    echo "UserData Base64 파일이 없습니다. 생성 중..."
    if [ -f "userdata-bootstrap.sh" ]; then
        base64 -w 0 userdata-bootstrap.sh > userdata-base64.txt
        echo "UserData Base64 인코딩 완료"
    else
        echo "ERROR: userdata-bootstrap.sh 파일을 찾을 수 없습니다"
        exit 1
    fi
fi

# UserData 읽기
USER_DATA=$(cat userdata-base64.txt)

echo "설정 정보:"
echo "  리전: $REGION"
echo "  VPC: $VPC_ID"
echo "  서브넷: $SUBNET_ID"
echo "  보안그룹: $SECURITY_GROUP_ID"
echo "  IAM Profile: $IAM_INSTANCE_PROFILE"
echo "  인스턴스 타입: $INSTANCE_TYPE"
echo "  스토리지: ${STORAGE_SIZE}GB"
echo "  AMI: $AMI_ID"
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
    --user-data file://userdata-bootstrap.sh \
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
    echo "🔍 로그 확인 방법:"
    echo "   aws logs describe-log-groups --log-group-name-prefix '/aws/ec2/bank-demo' --region $REGION"
    echo ""
    echo "🌐 서비스 접속 (인스턴스 준비 완료 후):"
    echo "   - 웹 애플리케이션: http://[PUBLIC_IP]"
    echo "   - 헬스체크: http://[PUBLIC_IP]/health"
    
else
    echo "❌ EC2 인스턴스 생성에 실패했습니다."
    echo "AWS CLI 오류를 확인해주세요."
    exit 1
fi 