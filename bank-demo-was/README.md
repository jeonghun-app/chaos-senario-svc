# Bank Demo WAS (Node.js Backend)

AWS Chaos Engineering Demo를 위한 금융권 WAS 백엔드 애플리케이션입니다.

## 🚀 빠른 시작

### 개발 환경 설정

```bash
# 의존성 설치
npm install

# 환경 변수 설정
cp .env.example .env

# 개발 서버 실행
npm run dev
```

### 프로덕션 환경 실행

```bash
# 프로덕션 모드로 실행
npm start
```

## 📁 프로젝트 구조

```
├── config/
│   └── config.js          # 애플리케이션 설정
├── routes/
│   ├── accounts.js        # 계좌 관리 API
│   ├── transactions.js    # 거래 처리 API
│   ├── health.js          # 헬스체크 API
│   └── metrics.js         # 메트릭/카오스 테스트 API
├── utils/
│   ├── logger.js          # Winston 로거
│   └── metrics.js         # CloudWatch 메트릭
├── logs/                  # 로그 파일 저장소
├── package.json           # 의존성 및 스크립트
└── server.js              # 메인 서버 파일
```

## 🌐 API 문서

### 기본 정보
- **Base URL**: `http://localhost:8080`
- **Content-Type**: `application/json`

### 엔드포인트

#### 헬스체크
- `GET /api/health` - 기본 헬스체크
- `GET /api/health/detailed` - 상세 헬스체크
- `GET /api/health/ready` - Readiness 프로브
- `GET /api/health/live` - Liveness 프로브

#### 계좌 관리
- `GET /api/accounts` - 계좌 목록 조회
- `GET /api/accounts/:accountNumber` - 특정 계좌 조회
- `POST /api/accounts` - 새 계좌 생성
- `PATCH /api/accounts/:accountNumber/balance` - 잔액 업데이트

#### 거래 처리
- `GET /api/transactions` - 거래 내역 조회
- `POST /api/transactions/transfer` - 계좌이체
- `POST /api/transactions` - 입출금 처리

#### 메트릭 및 카오스 테스트
- `GET /api/metrics` - 인스턴스 메트릭 조회
- `POST /api/metrics/simulate/latency` - 지연 시뮬레이션
- `POST /api/metrics/simulate/error` - 에러 시뮬레이션

## 🔧 환경 변수

개발 환경 (.env 파일):
```bash
INSTANCE_ID=local-dev
AWS_AVAILABILITY_ZONE=local
AWS_REGION=ap-northeast-2
NODE_ENV=development
PORT=8080
FRONTEND_URL=http://localhost:3000
CLOUDWATCH_ENABLED=false
LOG_LEVEL=debug
```

프로덕션 환경:
```bash
NODE_ENV=production
CLOUDWATCH_ENABLED=true
LOG_LEVEL=info
INSTANCE_ID=i-1234567890abcdef0
AWS_AVAILABILITY_ZONE=ap-northeast-2a
```

## 📊 모니터링

### CloudWatch 메트릭
- `BankDemo/WAS` 네임스페이스
- 자동 수집되는 메트릭:
  - RequestCount, ResponseTime
  - HTTP2XX, HTTP4XX, HTTP5XX
  - AccountsViewed, TransferCompleted
  - MemoryUsed, ProcessUptime

### 로깅
- Winston을 사용한 구조화된 로깅
- 로그 레벨: error, warn, info, debug
- 파일 로그: `logs/combined.log`, `logs/error.log`

## 🧪 테스트

### API 테스트 예시

```bash
# 헬스체크
curl http://localhost:8080/api/health

# 계좌 목록 조회
curl http://localhost:8080/api/accounts

# 새 계좌 생성
curl -X POST http://localhost:8080/api/accounts \
  -H "Content-Type: application/json" \
  -d '{
    "accountName": "테스트 계좌",
    "customerName": "홍길동",
    "accountType": "CHECKING",
    "initialBalance": 100000
  }'

# 계좌이체
curl -X POST http://localhost:8080/api/transactions/transfer \
  -H "Content-Type: application/json" \
  -d '{
    "fromAccount": "110-001-123456",
    "toAccount": "110-002-654321",
    "amount": 50000,
    "description": "테스트 이체"
  }'
```

### 카오스 엔지니어링 테스트

```bash
# 지연 시뮬레이션 (2초)
curl -X POST http://localhost:8080/api/metrics/simulate/latency \
  -H "Content-Type: application/json" \
  -d '{"duration": 2000}'

# 에러 시뮬레이션 (10% 확률)
curl -X POST http://localhost:8080/api/metrics/simulate/error \
  -H "Content-Type: application/json" \
  -d '{"errorType": "network", "errorRate": 0.1}'

# 메모리 압박 테스트 (200MB, 10초)
curl -X POST http://localhost:8080/api/metrics/simulate/memory-pressure \
  -H "Content-Type: application/json" \
  -d '{"sizeMB": 200, "durationMs": 10000}'
```

## 🔒 보안 기능

- **Helmet.js**: HTTP 헤더 보안 강화
- **CORS**: 제한된 Origin만 허용
- **Rate Limiting**: IP당 15분에 1000회 요청 제한
- **Input Validation**: Joi를 통한 입력 데이터 검증
- **Error Handling**: 민감한 정보 노출 방지

## 📦 의존성

### 주요 의존성
- `express`: 웹 프레임워크
- `winston`: 로깅
- `joi`: 입력 검증
- `helmet`: 보안 헤더
- `cors`: CORS 처리
- `aws-sdk`: AWS 서비스 연동

### 개발 의존성
- `nodemon`: 개발 서버 자동 재시작
- `jest`: 테스트 프레임워크
- `supertest`: API 테스트

## 🚀 배포

### PM2를 사용한 프로덕션 배포

```bash
# PM2로 실행
pm2 start server.js --name "bank-demo-was"

# 클러스터 모드로 실행
pm2 start server.js --name "bank-demo-was" -i max

# 저장 및 자동 시작 설정
pm2 save
pm2 startup
```

### Docker를 사용한 배포

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 8080
CMD ["npm", "start"]
```

## 🐛 문제 해결

### 일반적인 문제

1. **포트 충돌**: 8080 포트가 이미 사용 중인 경우
   ```bash
   export PORT=8081
   npm start
   ```

2. **CloudWatch 권한 오류**: AWS 자격 증명 확인
   ```bash
   aws configure list
   ```

3. **메모리 부족**: Node.js 힙 크기 조정
   ```bash
   node --max-old-space-size=1024 server.js
   ```

### 로그 확인

```bash
# 애플리케이션 로그
tail -f logs/combined.log

# 에러 로그만
tail -f logs/error.log

# PM2 로그 (프로덕션)
pm2 logs bank-demo-was
``` 