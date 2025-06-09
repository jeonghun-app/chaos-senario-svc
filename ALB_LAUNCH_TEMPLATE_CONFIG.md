# AWS Bank Demo - ALB & Auto Scaling 구성 가이드

## 🏗️ 인프라 구성 개요

```
Internet Gateway
    │
┌───▼─────────────────────────────────────────────────────────────┐
│                        VPC (us-east-1)                          │
│                        10.0.0.0/16                              │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Public Subnet │  │   Public Subnet │  │   Public Subnet │  │
│  │   us-east-1a    │  │   us-east-1b    │  │   us-east-1c    │  │
│  │   10.0.1.0/24   │  │   10.0.2.0/24   │  │   10.0.3.0/24   │  │
│  │                 │  │                 │  │                 │  │
│  │  ┌─────────────┐│  │  ┌─────────────┐│  │  ┌─────────────┐│  │
│  │  │     ALB     ││  │  │     ALB     ││  │  │     ALB     ││  │
│  │  │   Target    ││  │  │   Target    ││  │  │   Target    ││  │
│  │  └─────────────┘│  │  └─────────────┘│  │  └─────────────┘│  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│           │                     │                     │         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Private Subnet │  │  Private Subnet │  │  Private Subnet │  │
│  │   us-east-1a    │  │   us-east-1b    │  │   us-east-1c    │  │
│  │   10.0.11.0/24  │  │   10.0.12.0/24  │  │   10.0.13.0/24  │  │
│  │                 │  │                 │  │                 │  │
│  │  ┌─────────────┐│  │  ┌─────────────┐│  │  ┌─────────────┐│  │
│  │  │EC2 Instance ││  │  │EC2 Instance ││  │  │EC2 Instance ││  │
│  │  │Web + WAS    ││  │  │Web + WAS    ││  │  │Web + WAS    ││  │
│  │  │(nginx:80)   ││  │  │(nginx:80)   ││  │  │(nginx:80)   ││  │
│  │  └─────────────┘│  │  └─────────────┘│  │  └─────────────┘│  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## 1. VPC 구성

### VPC 생성
```bash
# VPC 생성
aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=bank-demo-vpc}]' \
    --region us-east-1

# Internet Gateway 생성 및 연결
aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=bank-demo-igw}]'

aws ec2 attach-internet-gateway \
    --vpc-id vpc-xxxxxxxxx \
    --internet-gateway-id igw-xxxxxxxxx
```

### 서브넷 생성
```bash
# Public Subnets
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=bank-demo-public-1a}]'
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=bank-demo-public-1b}]'
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.3.0/24 --availability-zone us-east-1c --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=bank-demo-public-1c}]'

# Private Subnets
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.11.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=bank-demo-private-1a}]'
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.12.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=bank-demo-private-1b}]'
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.13.0/24 --availability-zone us-east-1c --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=bank-demo-private-1c}]'
```

### NAT Gateway 생성 (Private 서브넷 인터넷 접근용)
```bash
# 각 AZ별 NAT Gateway 생성 (고가용성)
aws ec2 allocate-address --domain vpc --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=bank-demo-nat-1a}]'
aws ec2 create-nat-gateway --subnet-id subnet-xxxxxxxxx --allocation-id eipalloc-xxxxxxxxx --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value=bank-demo-nat-1a}]'

# 다른 AZ도 동일하게 생성...
```

## 2. Security Groups

### ALB Security Group
```json
{
    "GroupName": "bank-demo-alb-sg",
    "Description": "Security group for Bank Demo ALB",
    "VpcId": "vpc-xxxxxxxxx",
    "SecurityGroupRules": [
        {
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "CidrIpv4": "0.0.0.0/0",
            "Description": "HTTP from internet"
        },
        {
            "IpProtocol": "tcp",
            "FromPort": 443,
            "ToPort": 443,
            "CidrIpv4": "0.0.0.0/0",
            "Description": "HTTPS from internet"
        }
    ]
}
```

### EC2 Security Group
```json
{
    "GroupName": "bank-demo-ec2-sg",
    "Description": "Security group for Bank Demo EC2 instances",
    "VpcId": "vpc-xxxxxxxxx",
    "SecurityGroupRules": [
        {
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "ReferencedGroupInfo": {
                "GroupId": "sg-alb-xxxxxxxxx"
            },
            "Description": "HTTP from ALB"
        },
        {
            "IpProtocol": "tcp",
            "FromPort": 22,
            "ToPort": 22,
            "CidrIpv4": "10.0.0.0/16",
            "Description": "SSH from VPC"
        },
        {
            "IpProtocol": "tcp",
            "FromPort": 443,
            "ToPort": 443,
            "CidrIpv4": "0.0.0.0/0",
            "Description": "HTTPS for AWS services"
        }
    ]
}
```

## 3. IAM Role 생성

### EC2 Instance Role
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

### IAM Policy (CloudWatch + SSM)
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "ec2:DescribeVolumes",
                "ec2:DescribeTags",
                "logs:PutLogEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogStreams",
                "logs:DescribeLogGroups"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "ssm:PutParameter",
                "ssm:GetParameters",
                "ssm:UpdateParameter"
            ],
            "Resource": "arn:aws:ssm:us-east-1:*:parameter/bank-demo/*"
        }
    ]
}
```

## 4. Launch Template

### Launch Template JSON
```json
{
    "LaunchTemplateName": "bank-demo-template",
    "LaunchTemplateData": {
        "ImageId": "ami-0c02fb55956c7d316",
        "InstanceType": "t3.medium",
        "KeyName": "your-key-pair",
        "SecurityGroupIds": ["sg-xxxxxxxxx"],
        "IamInstanceProfile": {
            "Name": "BankDemo-EC2-InstanceProfile"
        },
        "UserData": "<base64-encoded-userdata-script.sh>",
        "TagSpecifications": [
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": "BankDemo-Instance"},
                    {"Key": "Project", "Value": "ChaosEngineering"},
                    {"Key": "Environment", "Value": "Demo"},
                    {"Key": "ChaosTarget", "Value": "true"}
                ]
            }
        ],
        "MetadataOptions": {
            "HttpTokens": "required",
            "HttpPutResponseHopLimit": 2,
            "HttpEndpoint": "enabled"
        },
        "Monitoring": {
            "Enabled": true
        }
    }
}
```

### UserData Base64 인코딩
```bash
# UserData 스크립트를 Base64로 인코딩
base64 -w 0 userdata-script.sh
```

## 5. Application Load Balancer

### ALB 생성
```bash
aws elbv2 create-load-balancer \
    --name bank-demo-alb \
    --subnets subnet-public-1a subnet-public-1b subnet-public-1c \
    --security-groups sg-xxxxxxxxx \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --tags Key=Name,Value=bank-demo-alb Key=Project,Value=ChaosEngineering
```

### Target Group 생성
```bash
aws elbv2 create-target-group \
    --name bank-demo-tg \
    --protocol HTTP \
    --port 80 \
    --vpc-id vpc-xxxxxxxxx \
    --health-check-enabled \
    --health-check-interval-seconds 30 \
    --health-check-path "/health" \
    --health-check-protocol HTTP \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --target-type instance \
    --tags Key=Name,Value=bank-demo-tg
```

### Listener 생성
```bash
aws elbv2 create-listener \
    --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:account:loadbalancer/app/bank-demo-alb/xxxxxxxxx \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-east-1:account:targetgroup/bank-demo-tg/xxxxxxxxx
```

## 6. Auto Scaling Group

### Auto Scaling Group 생성
```bash
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name bank-demo-asg \
    --launch-template LaunchTemplateName=bank-demo-template,Version=\$Latest \
    --min-size 3 \
    --max-size 9 \
    --desired-capacity 3 \
    --vpc-zone-identifier "subnet-private-1a,subnet-private-1b,subnet-private-1c" \
    --target-group-arns arn:aws:elasticloadbalancing:us-east-1:account:targetgroup/bank-demo-tg/xxxxxxxxx \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --default-cooldown 300 \
    --tags "Key=Name,Value=BankDemo-ASG,PropagateAtLaunch=true,ResourceId=bank-demo-asg,ResourceType=auto-scaling-group"
```

### Scaling Policies
```bash
# Scale Up Policy
aws autoscaling put-scaling-policy \
    --auto-scaling-group-name bank-demo-asg \
    --policy-name bank-demo-scale-up \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration file://scale-up-policy.json

# Scale Down Policy
aws autoscaling put-scaling-policy \
    --auto-scaling-group-name bank-demo-asg \
    --policy-name bank-demo-scale-down \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration file://scale-down-policy.json
```

### Scaling Policy JSON
```json
{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
        "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "ScaleOutCooldown": 300,
    "ScaleInCooldown": 300
}
```

## 7. CloudWatch 설정

### CloudWatch Dashboard
```json
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/bank-demo-alb/xxxxxxxxx"],
                    [".", "TargetResponseTime", ".", "."],
                    [".", "HTTPCode_Target_2XX_Count", ".", "."],
                    [".", "HTTPCode_Target_5XX_Count", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "ALB Metrics"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", "bank-demo-asg"],
                    [".", "GroupInServiceInstances", ".", "."],
                    [".", "GroupTotalInstances", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Auto Scaling Metrics"
            }
        }
    ]
}
```

## 8. AWS FIS 실험 템플릿

### FIS 실험 템플릿 (AZ-A 인스턴스 중단)
```json
{
    "description": "Stop EC2 instances in AZ us-east-1a for chaos engineering",
    "roleArn": "arn:aws:iam::account:role/FISRole",
    "actions": {
        "StopInstances": {
            "actionId": "aws:ec2:stop-instances",
            "parameters": {
                "startInstancesAfterDuration": "PT10M"
            },
            "targets": {
                "Instances": "ec2-instances-az-a"
            }
        }
    },
    "targets": {
        "ec2-instances-az-a": {
            "resourceType": "aws:ec2:instance",
            "resourceTags": {
                "ChaosTarget": "true"
            },
            "selectionMode": "ALL",
            "filters": [
                {
                    "path": "Placement.AvailabilityZone",
                    "values": ["us-east-1a"]
                }
            ]
        }
    },
    "stopConditions": [
        {
            "source": "aws:cloudwatch:alarm",
            "value": "arn:aws:cloudwatch:us-east-1:account:alarm:BankDemo-HighErrorRate"
        }
    ],
    "tags": {
        "Name": "BankDemo-AZ-A-Stop",
        "Project": "ChaosEngineering"
    }
}
```

## 9. 배포 명령어 실행 순서

```bash
# 1. VPC 및 네트워킹 설정
./setup-vpc.sh

# 2. Security Groups 생성
./setup-security-groups.sh

# 3. IAM Roles 생성
./setup-iam-roles.sh

# 4. Launch Template 생성
aws ec2 create-launch-template --cli-input-json file://launch-template.json

# 5. ALB 생성
./setup-alb.sh

# 6. Auto Scaling Group 생성
./setup-asg.sh

# 7. CloudWatch 대시보드 생성
aws cloudwatch put-dashboard --dashboard-name "BankDemo" --dashboard-body file://dashboard.json

# 8. FIS 실험 템플릿 생성
aws fis create-experiment-template --cli-input-json file://fis-template.json
```

## 10. 헬스체크 및 모니터링

### ALB 헬스체크 설정
- **Path**: `/health`
- **Port**: `80` (nginx)
- **Protocol**: `HTTP`
- **Interval**: `30초`
- **Timeout**: `5초`
- **Healthy threshold**: `2`
- **Unhealthy threshold**: `3`

### CloudWatch 알람
```bash
# High Error Rate Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "BankDemo-HighErrorRate" \
    --alarm-description "High 5XX error rate" \
    --metric-name HTTPCode_Target_5XX_Count \
    --namespace AWS/ApplicationELB \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2
```

이 구성으로 카오스 엔지니어링 데모를 위한 완전한 AWS 인프라가 준비됩니다. 