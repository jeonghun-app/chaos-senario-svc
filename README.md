# AWS Chaos Engineering Demo - 금융권 웹/WAS 애플리케이션

## 📋 프로젝트 개요

이 프로젝트는 AWS에서 3-AZ 환경의 웹/WAS 카오스 엔지니어링 데모를 위한 금융권 애플리케이션입니다. Auto Scaling과 가용성 테스트를 위해 설계되었으며, AWS FIS(Fault Injection Simulator)를 통한 장애 시나리오 테스트를 지원합니다.

## 🏗️ 아키텍처

```
Route 53 → ALB(Zone A/B/C) → Auto Scaling Group
                              ├── EC2 Instance (Web + WAS)
                              ├── EC2 Instance (Web + WAS)
                              └── EC2 Instance (Web + WAS)
```

### 주요 구성 요소
- **Web Frontend**: Next.js 기반 금융 서비스 UI
- **WAS Backend**: Node.js Express 기반 REST API 서버
- **Auto Scaling**: EC2 인스턴스 자동 확장/축소
- **CloudWatch**: 메트릭 모니터링 및 알람
- **AWS FIS**: 카오스 엔지니어링 실험

## 🚀 데모 시나리오

### 단계별 진행 내용

| 단계 | 시점 | 내용 | 기대 결과 |
|------|------|------|-----------|
| 0. 사전 설정 | T-1주 | 아키텍처 구성, FIS 템플릿, CloudWatch 알람 설정 | 데모 환경 완료 |
| 1. 소개 | T-15분 | 시나리오 설명, 대시보드 베이스라인 확인 | 정상 상태 인지 |
| 2. 워밍업 | T-5분 | AWS Synthetics Canary 200 TPS 발사 | 안정적 200 TPS |
| 3. 카오스 시작 | T+0분 | AZ-A EC2 인스턴스 중단 | FIS "Running" |
| 4. 장애 감지 | T+1분 | ALB가 Zone B/C로만 트래픽 전송 | 5XX < 4% |
| 5. 용량 복구 | T+2분 | Auto Scaling으로 새 EC2 기동 | 용량 100% 회복 |
| 6. 안정성 확인 | T+4분 | 지표 정상화 | RTO ≤ 10분 |
| 7. 실험 종료 | T+8분 | FIS StopExperiment | FIS "Completed" |
| 8. 자동 보고 | T+9분 | Step Functions → Bedrock → PDF 생성 | 보고서 자동 생성 |

### 성공 기준 (KPI)
- **RTO**: ≤ 10분 (FIS 시작 → 정상 응답 회복)
- **ALB 5XX**: 피크 ≤ 5% & 3분 이내 < 1%
- **P95 Latency**: 피크 ≤ 2× Baseline & 5분 이내 정상화
- **자동 보고**: 훈련 종료 ≤ 15분 내 PDF 초안 생성

## 📁 프로젝트 구조

```
├── bank-demo-web/          # Next.js 웹 프론트엔드
├── bank-demo-was/          # Node.js WAS 백엔드
│   ├── config/             # 설정 파일
│   ├── routes/             # API 라우트
│   │   ├── accounts.js     # 계좌 관리 API
│   │   ├── transactions.js # 거래 처리 API
│   │   ├── health.js       # 헬스체크 API
│   │   └── metrics.js      # 메트릭/카오스 API
│   ├── utils/              # 유틸리티
│   │   ├── logger.js       # 로깅
│   │   └── metrics.js      # CloudWatch 메트릭
│   ├── package.json        # 의존성 관리
│   └── server.js           # 메인 서버
├── userdata-script.sh      # EC2 Auto Scaling UserData
└── README.md               # 프로젝트 문서
```

## 🛠️ 설치 및 실행

### 1. WAS (백엔드) 설치

```bash
cd bank-demo-was
npm install
npm start
```

### 2. Web (프론트엔드) 설치

```bash
cd bank-demo-web
npm install
npm run build
npm start
```

### 3. Auto Scaling 환경에서 실행

EC2 Launch Template의 UserData에 `userdata-script.sh` 내용을 추가하면 자동으로 설치됩니다.

## 🔧 환경 변수

### WAS 환경 변수
```bash
INSTANCE_ID=i-1234567890abcdef0      # EC2 인스턴스 ID
AWS_AVAILABILITY_ZONE=ap-northeast-2a # 가용영역
AWS_REGION=ap-northeast-2             # AWS 리전
NODE_ENV=production                   # 실행 환경
PORT=8080                            # WAS 포트
FRONTEND_URL=http://localhost:3000   # 프론트엔드 URL
CLOUDWATCH_ENABLED=true              # CloudWatch 메트릭 활성화
LOG_LEVEL=info                       # 로그 레벨
```

## 🌐 API 엔드포인트

### 헬스체크
- `GET /api/health` - 기본 헬스체크
- `GET /api/health/detailed` - 상세 헬스체크
- `GET /api/health/ready` - Readiness 프로브
- `GET /api/health/live` - Liveness 프로브

### 계좌 관리
- `GET /api/accounts` - 계좌 목록 조회
- `GET /api/accounts/:accountNumber` - 특정 계좌 조회
- `POST /api/accounts` - 새 계좌 생성
- `PATCH /api/accounts/:accountNumber/balance` - 잔액 업데이트
- `PATCH /api/accounts/:accountNumber/status` - 계좌 상태 변경

### 거래 처리
- `GET /api/transactions` - 거래 내역 조회
- `GET /api/transactions/:transactionId` - 특정 거래 조회
- `POST /api/transactions/transfer` - 계좌이체
- `POST /api/transactions` - 입출금 처리
- `GET /api/transactions/stats/summary` - 거래 통계

### 메트릭 및 카오스 테스트
- `GET /api/metrics` - 인스턴스 메트릭 조회
- `POST /api/metrics/send-system` - 시스템 메트릭 전송
- `POST /api/metrics/simulate/latency` - 지연 시뮬레이션
- `POST /api/metrics/simulate/error` - 에러 시뮬레이션
- `POST /api/metrics/simulate/memory-pressure` - 메모리 압박 시뮬레이션
- `GET /api/metrics/load-test` - 부하 테스트

## 📊 모니터링

### CloudWatch 메트릭
- **BankDemo/WAS** 네임스페이스
  - RequestCount, ResponseTime
  - HTTP2XX, HTTP4XX, HTTP5XX
  - AccountsViewed, TransferCompleted
  - MemoryUsed, ProcessUptime

### CloudWatch 로그
- `/aws/ec2/bank-demo` 로그 그룹
  - Application 로그
  - UserData 실행 로그

## 🎯 카오스 엔지니어링 기능

### 1. 지연 시뮬레이션
```bash
curl -X POST http://localhost:8080/api/metrics/simulate/latency \
  -H "Content-Type: application/json" \
  -d '{"duration": 2000}'
```

### 2. 에러 시뮬레이션
```bash
curl -X POST http://localhost:8080/api/metrics/simulate/error \
  -H "Content-Type: application/json" \
  -d '{"errorType": "network", "errorRate": 0.1}'
```

### 3. 메모리 압박 시뮬레이션
```bash
curl -X POST http://localhost:8080/api/metrics/simulate/memory-pressure \
  -H "Content-Type: application/json" \
  -d '{"sizeMB": 200, "durationMs": 10000}'
```

### 4. 부하 테스트
```bash
curl "http://localhost:8080/api/metrics/load-test?operations=5000"
```

## 🔒 보안 고려사항

- **Helmet.js**: HTTP 헤더 보안
- **Rate Limiting**: 요청 제한 (IP당 15분에 1000회)
- **Input Validation**: Joi를 통한 입력 검증
- **CORS**: 제한된 Origin 허용
- **에러 처리**: 민감한 정보 노출 방지

## 🚀 AWS 인프라 구성

### 필수 AWS 리소스
1. **VPC**: 3개 AZ에 걸친 서브넷
2. **ALB**: Application Load Balancer + 타겟 그룹
3. **Auto Scaling Group**: Launch Template + 정책
4. **CloudWatch**: 대시보드 + 알람
5. **AWS FIS**: 실험 템플릿
6. **Step Functions**: 자동 보고 워크플로우

### Launch Template 설정
```json
{
  "ImageId": "ami-0c2acfcb2ac4d02a0",
  "InstanceType": "t3.medium",
  "SecurityGroupIds": ["sg-xxxxxxxxx"],
  "IamInstanceProfile": {
    "Name": "BankDemo-EC2-Role"
  },
  "UserData": "<base64-encoded-userdata-script.sh>",
  "TagSpecification": [{
    "ResourceType": "instance",
    "Tags": [
      {"Key": "Name", "Value": "BankDemo-Instance"},
      {"Key": "ChaosTarget", "Value": "true"}
    ]
  }]
}
```

### IAM 권한
EC2 인스턴스에 필요한 권한:
- CloudWatch 메트릭/로그 전송
- Systems Manager Parameter Store 접근
- EC2 메타데이터 조회

## 📝 개발 및 기여

### 로컬 개발 환경
```bash
# WAS 개발 서버
cd bank-demo-was
npm run dev

# Web 개발 서버  
cd bank-demo-web
npm run dev
```

### 로그 확인
```bash
# WAS 로그
tail -f bank-demo-was/logs/combined.log

# PM2 로그 (프로덕션)
pm2 logs bank-demo-was
```

## 📄 라이선스

MIT License

## 👥 지원

문의사항이나 이슈가 있으시면 AWS 데모 팀에 연락해 주세요.

---

**Note**: 이 프로젝트는 교육 및 데모 목적으로 설계되었습니다. 프로덕션 환경에서 사용하기 전에 추가적인 보안 검토와 성능 테스트가 필요합니다. 