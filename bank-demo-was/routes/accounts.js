const express = require('express');
const router = express.Router();
const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');
const { sendMetric } = require('../utils/metrics');

// 데모용 인메모리 데이터 저장소
let accounts = [];

// 데모 데이터 초기화
function initializeDemoData() {
  if (accounts.length === 0) {
    const accountTypes = ['CHECKING', 'SAVINGS', 'DEPOSIT'];
    const customerNames = [
      '김철수', '이영희', '박민수', '최지원', '정현우',
      '한미경', '조성호', '강은지', '윤서준', '임나영'
    ];

    for (let i = 1; i <= 50; i++) {
      accounts.push({
        id: i,
        accountNumber: `110-${String(i).padStart(3, '0')}-${Math.floor(Math.random() * 1000000).toString().padStart(6, '0')}`,
        accountName: `${customerNames[i % customerNames.length]}의 계좌`,
        customerName: customerNames[i % customerNames.length],
        accountType: accountTypes[i % accountTypes.length],
        balance: Math.floor(Math.random() * 10000000) + 100000, // 10만원 ~ 1천만원
        createdAt: new Date(Date.now() - Math.floor(Math.random() * 365 * 24 * 60 * 60 * 1000)).toISOString(),
        updatedAt: new Date().toISOString(),
        status: 'ACTIVE'
      });
    }
    logger.info(`Initialized ${accounts.length} demo accounts`);
  }
}

// 초기 데이터 로드
initializeDemoData();

// 유효성 검사 스키마
const accountSchema = Joi.object({
  accountName: Joi.string().required().min(2).max(50),
  customerName: Joi.string().required().min(2).max(30),
  accountType: Joi.string().valid('CHECKING', 'SAVINGS', 'DEPOSIT').required(),
  initialBalance: Joi.number().min(0).max(100000000).default(0)
});

const balanceUpdateSchema = Joi.object({
  amount: Joi.number().required(),
  type: Joi.string().valid('DEPOSIT', 'WITHDRAWAL').required(),
  description: Joi.string().max(100).default('')
});

// 모든 계좌 조회
router.get('/', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const startIndex = (page - 1) * limit;
    const endIndex = page * limit;

    const paginatedAccounts = accounts.slice(startIndex, endIndex);
    
    // CloudWatch 메트릭 전송
    await sendMetric('AccountsViewed', 1, req.instanceId, req.availabilityZone);
    
    logger.info(`Accounts retrieved - Page: ${page}, Count: ${paginatedAccounts.length}`);

    res.json({
      accounts: paginatedAccounts,
      pagination: {
        page,
        limit,
        total: accounts.length,
        totalPages: Math.ceil(accounts.length / limit)
      },
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error retrieving accounts:', error);
    await sendMetric('AccountErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to retrieve accounts' });
  }
});

// 특정 계좌 조회
router.get('/:accountNumber', async (req, res) => {
  try {
    const { accountNumber } = req.params;
    const account = accounts.find(acc => acc.accountNumber === accountNumber);

    if (!account) {
      await sendMetric('AccountNotFound', 1, req.instanceId, req.availabilityZone);
      return res.status(404).json({ 
        error: 'Account not found',
        accountNumber,
        instance: req.instanceId
      });
    }

    await sendMetric('AccountViewed', 1, req.instanceId, req.availabilityZone);
    logger.info(`Account viewed: ${accountNumber}`);

    res.json({
      account,
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error retrieving account:', error);
    await sendMetric('AccountErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to retrieve account' });
  }
});

// 새 계좌 생성
router.post('/', async (req, res) => {
  try {
    const { error, value } = accountSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ 
        error: 'Validation failed',
        details: error.details[0].message 
      });
    }

    const newAccount = {
      id: accounts.length + 1,
      accountNumber: `110-${String(accounts.length + 1).padStart(3, '0')}-${Math.floor(Math.random() * 1000000).toString().padStart(6, '0')}`,
      accountName: value.accountName,
      customerName: value.customerName,
      accountType: value.accountType,
      balance: value.initialBalance,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: 'ACTIVE'
    };

    accounts.push(newAccount);
    
    await sendMetric('AccountCreated', 1, req.instanceId, req.availabilityZone);
    logger.info(`New account created: ${newAccount.accountNumber}`);

    res.status(201).json({
      account: newAccount,
      message: 'Account created successfully',
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error creating account:', error);
    await sendMetric('AccountErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to create account' });
  }
});

// 계좌 잔액 업데이트
router.patch('/:accountNumber/balance', async (req, res) => {
  try {
    const { accountNumber } = req.params;
    const { error, value } = balanceUpdateSchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ 
        error: 'Validation failed',
        details: error.details[0].message 
      });
    }

    const account = accounts.find(acc => acc.accountNumber === accountNumber);
    if (!account) {
      return res.status(404).json({ error: 'Account not found' });
    }

    const { amount, type, description } = value;
    
    if (type === 'WITHDRAWAL' && account.balance < amount) {
      await sendMetric('InsufficientFunds', 1, req.instanceId, req.availabilityZone);
      return res.status(400).json({ 
        error: 'Insufficient funds',
        currentBalance: account.balance,
        requestedAmount: amount
      });
    }

    const previousBalance = account.balance;
    account.balance = type === 'DEPOSIT' 
      ? account.balance + amount 
      : account.balance - amount;
    account.updatedAt = new Date().toISOString();

    await sendMetric(type === 'DEPOSIT' ? 'MoneyDeposited' : 'MoneyWithdrawn', amount, req.instanceId, req.availabilityZone);
    logger.info(`Balance updated - Account: ${accountNumber}, Type: ${type}, Amount: ${amount}`);

    res.json({
      account,
      transaction: {
        type,
        amount,
        description,
        previousBalance,
        newBalance: account.balance,
        timestamp: account.updatedAt
      },
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone
      }
    });
  } catch (error) {
    logger.error('Error updating balance:', error);
    await sendMetric('AccountErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to update balance' });
  }
});

// 계좌 상태 변경
router.patch('/:accountNumber/status', async (req, res) => {
  try {
    const { accountNumber } = req.params;
    const { status } = req.body;

    if (!['ACTIVE', 'SUSPENDED', 'CLOSED'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }

    const account = accounts.find(acc => acc.accountNumber === accountNumber);
    if (!account) {
      return res.status(404).json({ error: 'Account not found' });
    }

    account.status = status;
    account.updatedAt = new Date().toISOString();

    await sendMetric('AccountStatusChanged', 1, req.instanceId, req.availabilityZone);
    logger.info(`Account status changed - Account: ${accountNumber}, Status: ${status}`);

    res.json({
      account,
      message: `Account status changed to ${status}`,
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error changing account status:', error);
    await sendMetric('AccountErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to change account status' });
  }
});

module.exports = router; 