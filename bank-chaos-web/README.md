# Bank Chaos Web - Monitoring Dashboard

AWS Chaos Engineering Demo를 위한 실시간 모니터링 및 카오스 실험 관리 대시보드입니다.

## 🎯 목적

이 웹 애플리케이션은 다음을 목적으로 합니다:
- **실시간 모니터링**: 은행 서비스의 실시간 상태 관찰
- **카오스 실험 관리**: FIS 실험 시작/중지/모니터링
- **성능 분석**: CloudWatch 메트릭 시각화
- **자동 보고**: 실험 결과 분석 및 보고서 생성

## 🚀 주요 기능

### 실시간 대시보드
- **서비스 상태**: 은행 서비스 전체 건강 상태
- **메트릭 모니터링**: P95 응답시간, 5XX 에러율, 요청 수
- **인스턴스 상태**: EC2 인스턴스 개수 및 건강 상태
- **실험 상태**: 현재 실행 중인 카오스 실험

### FIS 실험 관리
- **실험 목록**: 사전 정의된 카오스 실험 템플릿
- **실험 제어**: 실험 시작/중지 기능
- **실시간 모니터링**: 실험 진행 상황 추적
- **결과 저장**: 실험 결과 자동 저장

### CloudWatch 연동
- **메트릭 조회**: ALB, EC2, 커스텀 메트릭
- **실시간 차트**: 시계열 데이터 시각화
- **알람 관리**: 임계값 기반 알람 설정
- **로그 분석**: CloudWatch Logs 연동

### 자동 보고 시스템
- **Step Functions**: 보고서 생성 워크플로우
- **Bedrock 연동**: AI 기반 분석 보고서
- **PDF 생성**: 다운로드 가능한 보고서
- **히스토리 관리**: 과거 실험 결과 조회

## 📁 프로젝트 구조

```
bank-chaos-web/
├── src/
│   ├── app/
│   │   ├── api/                    # Next.js API Routes
│   │   │   ├── experiments/        # FIS 실험 관리 API
│   │   │   ├── metrics/            # CloudWatch 메트릭 API
│   │   │   ├── reports/            # 보고서 생성 API
│   │   │   └── stepfunctions/      # Step Functions API
│   │   ├── dashboard/              # 대시보드 페이지
│   │   ├── experiments/            # 실험 관리 페이지
│   │   ├── reports/                # 보고서 페이지
│   │   ├── page.tsx                # 메인 페이지
│   │   └── layout.tsx              # 레이아웃
│   ├── components/
│   │   ├── charts/                 # 차트 컴포넌트
│   │   ├── monitoring/             # 모니터링 위젯
│   │   └── controls/               # 실험 제어 컴포넌트
│   └── utils/
│       ├── aws/                    # AWS SDK 유틸리티
│       └── helpers/                # 헬퍼 함수
├── package.json
├── next.config.js
├── tailwind.config.js
└── tsconfig.json
```

## 🛠️ 기술 스택

### Frontend
- **Next.js 15**: React 프레임워크
- **TypeScript**: 정적 타입 검사
- **Tailwind CSS**: 유틸리티 CSS 프레임워크
- **Recharts**: 차트 라이브러리

### Backend (API Routes)
- **Next.js API Routes**: 서버리스 API
- **AWS SDK v3**: AWS 서비스 연동
- **Date-fns**: 날짜 처리

### AWS 서비스 연동
- **FIS (Fault Injection Simulator)**: 카오스 실험
- **CloudWatch**: 메트릭 및 로그
- **Step Functions**: 워크플로우 관리
- **Bedrock**: AI 분석 보고서

## 🚀 빠른 시작

### 개발 환경 설정

```bash
# 의존성 설치
npm install

# 환경 변수 설정
cp .env.example .env.local

# 개발 서버 실행 (포트 3001)
npm run dev
```

### 환경 변수

```bash
# .env.local
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# Optional: AWS Role 사용 시
AWS_ROLE_ARN=arn:aws:iam::account:role/ChaosEngineeringRole

# 은행 서비스 연동
BANK_WAS_URL=http://localhost:8080
BANK_WEB_URL=http://localhost:3000
```

## 📊 API 엔드포인트

### FIS 실험 관리
```bash
# 실험 목록 조회
GET /api/experiments

# 특정 실험 시작
POST /api/experiments/{experimentId}/start

# 실험 중지
POST /api/experiments/{experimentId}/stop

# 실험 상태 조회
GET /api/experiments/{experimentId}/status
```

### CloudWatch 메트릭
```bash
# 서비스 상태 메트릭
GET /api/metrics/service-status

# 특정 메트릭 조회
GET /api/metrics/custom?metric=ResponseTime&period=300

# 알람 목록
GET /api/metrics/alarms
```

### 보고서 생성
```bash
# 보고서 생성 시작
POST /api/reports/generate

# 보고서 상태 확인
GET /api/reports/{reportId}/status

# 보고서 다운로드
GET /api/reports/{reportId}/download
```

## 🎯 데모 시나리오 (10단계)

### T-15min: 베이스라인 측정
- 정상 상태 메트릭 수집
- 기준 성능 지표 설정

### T-10min: 실험 준비
- FIS 실험 템플릿 확인
- 모니터링 시스템 준비

### T-5min: 모니터링 확인
- 대시보드 상태 점검
- 알람 설정 확인

### T-0min: Chaos 실험 시작
- AZ-A 인스턴스 중단 실험 시작
- 실시간 모니터링 활성화

### T+2min: AZ-A 인스턴스 중단
- FIS를 통한 EC2 인스턴스 중단
- ALB 트래픽 재분산 모니터링

### T+5min: 트래픽 재분산
- 건강한 인스턴스로 트래픽 이동
- 응답 시간 및 에러율 추적

### T+8min: 복구 감지
- 서비스 복구 확인
- 성능 지표 정상화

### T+10min: 실험 종료
- FIS 실험 중지
- 인스턴스 복구 시작

### T+15min: 결과 분석
- 실험 데이터 수집
- 성능 영향 분석

### T+20min: 보고서 생성
- AI 기반 분석 보고서
- PDF 다운로드 제공

## 🔧 성능 목표

### RTO (Recovery Time Objective)
- **목표**: ≤ 10분
- **측정**: 장애 발생부터 서비스 복구까지

### 가용성
- **목표**: 5XX 에러율 ≤ 5%
- **측정**: ALB 5XX 에러 비율

### 응답 성능
- **목표**: P95 Latency ≤ 2× Baseline
- **측정**: 정상 상태 대비 응답 시간

## 🔒 보안 고려사항

### 접근 제어
- 관리자만 카오스 실험 실행 가능
- AWS IAM 역할 기반 권한 관리
- VPN 또는 내부 네트워크에서만 접근

### 실험 안전장치
- 실험 자동 중지 메커니즘
- 최대 실행 시간 제한
- 비상 중지 기능

### 데이터 보호
- 실험 결과 암호화 저장
- 민감한 정보 마스킹
- 감사 로그 기록

## 📈 모니터링 메트릭

### 비즈니스 메트릭
- 거래 성공률
- 평균 거래 시간
- 동시 사용자 수

### 기술 메트릭
- HTTP 응답 시간
- 에러율 (4XX, 5XX)
- 처리량 (RPS)

### 인프라 메트릭
- EC2 인스턴스 상태
- ALB 상태
- Auto Scaling 활동

## 🤝 Contributing

1. 기능 요청이나 버그 리포트는 이슈로 등록
2. Pull Request 전에 테스트 실행
3. 코드 스타일 가이드 준수

## 📝 라이센스

이 프로젝트는 AWS Chaos Engineering 데모 목적으로 제작되었습니다.
