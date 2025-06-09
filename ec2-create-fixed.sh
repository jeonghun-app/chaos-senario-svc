#!/bin/bash

# AWS Bank Demo - EC2 Instance 생성 (문제 해결 버전)
# GitHub 의존성 없이 완전한 단일 스크립트 사용

echo "====================================="
echo "AWS Bank Demo EC2 Instance 생성 (Fixed)"
echo "====================================="

# 변수 설정
REGION="us-east-1"
SUBNET_ID="subnet-0965c00cce99ea63c"
SECURITY_GROUP_ID="sg-0d8ba709de8330b24"
IAM_INSTANCE_PROFILE="arn:aws:iam::081041735764:instance-profile/EC2Sec"
INSTANCE_TYPE="t3.medium"
STORAGE_SIZE="100"
AMI_ID="ami-0340d40dae6a2cbcf"  # Amazon Linux 2023

echo "설정 정보:"
echo "  리전: $REGION"
echo "  서브넷: $SUBNET_ID"
echo "  보안그룹: $SECURITY_GROUP_ID"
echo "  인스턴스 타입: $INSTANCE_TYPE"
echo "  스토리지: ${STORAGE_SIZE}GB"
echo "  UserData: userdata-complete.sh ($(wc -c < userdata-complete.sh) bytes)"
echo ""

# EC2 인스턴스 생성
echo "EC2 인스턴스 생성 중..."

INSTANCE_ID=$(aws ec2 run-instances \
    --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --subnet-id $SUBNET_ID \
    --security-group-ids $SECURITY_GROUP_ID \
    --iam-instance-profile Arn=$IAM_INSTANCE_PROFILE \
    --associate-public-ip-address \
    --user-data file://userdata-complete.sh \
    --block-device-mappings '[
        {
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": '$STORAGE_SIZE',
                "VolumeType": "gp3",
                "DeleteOnTermination": true,
                "Encrypted": true
            }
        }
    ]' \
    --tag-specifications '
        ResourceType=instance,Tags=[
            {Key=Name,Value=BankDemo-WebWAS-Fixed},
            {Key=Project,Value=ChaosEngineering},
            {Key=Environment,Value=Demo},
            {Key=ChaosTarget,Value=true},
            {Key=ScriptVersion,Value=Complete}
        ]
    ' \
    --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled' \
    --monitoring 'Enabled=true' \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ $? -eq 0 ] && [ ! -z "$INSTANCE_ID" ]; then
    echo ""
    echo "✅ EC2 인스턴스가 성공적으로 생성되었습니다!"
    echo "   인스턴스 ID: $INSTANCE_ID"
    echo ""
    
    # 인스턴스 정보 조회
    echo "인스턴스 정보 조회 중..."
    aws ec2 describe-instances \
        --region $REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output table
    
    # 퍼블릭 IP 가져오기 (몇 초 후)
    echo ""
    echo "퍼블릭 IP 할당 대기 중..."
    sleep 10
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region $REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    echo ""
    echo "📋 인스턴스 정보:"
    echo "   Instance ID: $INSTANCE_ID"
    echo "   Public IP: $PUBLIC_IP"
    echo "   Region: $REGION"
    echo ""
    echo "🔄 진행 상황:"
    echo "   1. 인스턴스 시작: 완료 ✅"
    echo "   2. UserData 실행: 진행중 (5-10분 소요)"
    echo "   3. 서비스 준비: 대기중"
    echo ""
    echo "🌐 접속 정보 (서비스 준비 완료 후):"
    echo "   - 웹 애플리케이션: http://$PUBLIC_IP"
    echo "   - 헬스체크: http://$PUBLIC_IP/health"
    echo "   - API: http://$PUBLIC_IP/api/health"
    echo ""
    echo "📊 모니터링:"
    echo "   aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION"
    echo "   aws logs tail /aws/ec2/userdata --follow --region $REGION"
    
else
    echo "❌ EC2 인스턴스 생성에 실패했습니다."
    exit 1
fi

echo ""
echo "🎯 성공! 인스턴스가 생성되었습니다."
echo "   약 10분 후 http://$PUBLIC_IP 에서 서비스를 확인할 수 있습니다." 