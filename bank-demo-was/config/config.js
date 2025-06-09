module.exports = {
  server: {
    port: process.env.PORT || 8080,
    host: '0.0.0.0'
  },
  aws: {
    region: process.env.AWS_REGION || 'ap-northeast-2',
    instanceId: process.env.INSTANCE_ID || 'local-dev',
    availabilityZone: process.env.AWS_AVAILABILITY_ZONE || 'local'
  },
  cors: {
    origin: process.env.FRONTEND_URL || 'http://localhost:3000',
    credentials: true
  },
  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 1000 // limit each IP to 1000 requests per windowMs
  },
  cloudwatch: {
    namespace: 'BankDemo/WAS',
    enabled: process.env.CLOUDWATCH_ENABLED !== 'false'
  },
  demo: {
    // 데모용 계좌 데이터 설정
    sampleAccountsCount: 100,
    maxTransactionAmount: 1000000,
    transactionTypes: ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER'],
    accountTypes: ['CHECKING', 'SAVINGS', 'DEPOSIT']
  }
}; 