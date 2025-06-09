const express = require('express');
const router = express.Router();
const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');
const { sendMetric } = require('../utils/metrics');

// 데모용 인메모리 거래 데이터
let transactions = [];

// 거래 데이터 초기화
function initializeTransactionData() {
  if (transactions.length === 0) {
    const transactionTypes = ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'FEE'];
    const descriptions = [
      '입금', '출금', '이체', '수수료',
      'ATM 출금', '온라인 이체', '급여 입금', '자동이체'
    ];

    for (let i = 1; i <= 100; i++) {
      const type = transactionTypes[Math.floor(Math.random() * transactionTypes.length)];
      transactions.push({
        id: i,
        transactionId: `TXN${Date.now()}${String(i).padStart(4, '0')}`,
        accountNumber: `110-${String(Math.floor(Math.random() * 50) + 1).padStart(3, '0')}-${Math.floor(Math.random() * 1000000).toString().padStart(6, '0')}`,
        type,
        amount: Math.floor(Math.random() * 1000000) + 1000,
        description: descriptions[Math.floor(Math.random() * descriptions.length)],
        balanceBefore: Math.floor(Math.random() * 10000000),
        balanceAfter: 0, // 계산됨
        status: Math.random() > 0.05 ? 'COMPLETED' : 'FAILED', // 95% 성공률
        createdAt: new Date(Date.now() - Math.floor(Math.random() * 30 * 24 * 60 * 60 * 1000)).toISOString(),
        processedAt: new Date(Date.now() - Math.floor(Math.random() * 30 * 24 * 60 * 60 * 1000)).toISOString()
      });
    }

    // balanceAfter 계산
    transactions.forEach(tx => {
      if (tx.status === 'COMPLETED') {
        tx.balanceAfter = tx.type === 'DEPOSIT' 
          ? tx.balanceBefore + tx.amount 
          : tx.balanceBefore - tx.amount;
      } else {
        tx.balanceAfter = tx.balanceBefore;
      }
    });

    logger.info(`Initialized ${transactions.length} demo transactions`);
  }
}

// 초기 데이터 로드
initializeTransactionData();

// 유효성 검사 스키마
const transferSchema = Joi.object({
  fromAccount: Joi.string().required(),
  toAccount: Joi.string().required(),
  amount: Joi.number().min(1).max(50000000).required(),
  description: Joi.string().max(100).default('계좌이체')
});

const transactionSchema = Joi.object({
  accountNumber: Joi.string().required(),
  type: Joi.string().valid('DEPOSIT', 'WITHDRAWAL').required(),
  amount: Joi.number().min(1).max(50000000).required(),
  description: Joi.string().max(100).default('')
});

// 모든 거래 내역 조회
router.get('/', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const accountNumber = req.query.accountNumber;
    const type = req.query.type;
    const status = req.query.status;

    let filteredTransactions = [...transactions];

    // 필터링
    if (accountNumber) {
      filteredTransactions = filteredTransactions.filter(tx => 
        tx.accountNumber === accountNumber
      );
    }
    if (type) {
      filteredTransactions = filteredTransactions.filter(tx => tx.type === type);
    }
    if (status) {
      filteredTransactions = filteredTransactions.filter(tx => tx.status === status);
    }

    // 정렬 (최신순)
    filteredTransactions.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    // 페이지네이션
    const startIndex = (page - 1) * limit;
    const endIndex = page * limit;
    const paginatedTransactions = filteredTransactions.slice(startIndex, endIndex);

    await sendMetric('TransactionsViewed', paginatedTransactions.length, req.instanceId, req.availabilityZone);

    res.json({
      transactions: paginatedTransactions,
      pagination: {
        page,
        limit,
        total: filteredTransactions.length,
        totalPages: Math.ceil(filteredTransactions.length / limit)
      },
      filters: { accountNumber, type, status },
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error retrieving transactions:', error);
    await sendMetric('TransactionErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to retrieve transactions' });
  }
});

// 특정 거래 조회
router.get('/:transactionId', async (req, res) => {
  try {
    const { transactionId } = req.params;
    const transaction = transactions.find(tx => tx.transactionId === transactionId);

    if (!transaction) {
      return res.status(404).json({ 
        error: 'Transaction not found',
        transactionId 
      });
    }

    await sendMetric('TransactionViewed', 1, req.instanceId, req.availabilityZone);

    res.json({
      transaction,
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error retrieving transaction:', error);
    await sendMetric('TransactionErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to retrieve transaction' });
  }
});

// 계좌이체 처리
router.post('/transfer', async (req, res) => {
  try {
    const { error, value } = transferSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ 
        error: 'Validation failed',
        details: error.details[0].message 
      });
    }

    const { fromAccount, toAccount, amount, description } = value;

    // 송금 계좌와 수신 계좌가 같은지 확인
    if (fromAccount === toAccount) {
      return res.status(400).json({ error: 'Cannot transfer to the same account' });
    }

    // 데모용 처리 지연 시뮬레이션 (50-200ms)
    const processingDelay = Math.floor(Math.random() * 150) + 50;
    await new Promise(resolve => setTimeout(resolve, processingDelay));

    // 성공/실패 시뮬레이션 (98% 성공률)
    const isSuccess = Math.random() > 0.02;
    const status = isSuccess ? 'COMPLETED' : 'FAILED';

    const transaction = {
      id: transactions.length + 1,
      transactionId: `TXN${Date.now()}${String(transactions.length + 1).padStart(4, '0')}`,
      type: 'TRANSFER',
      fromAccount,
      toAccount,
      amount,
      description,
      status,
      processingTime: processingDelay,
      createdAt: new Date().toISOString(),
      processedAt: new Date().toISOString(),
      failureReason: !isSuccess ? 'Network timeout' : null
    };

    transactions.push(transaction);

    if (isSuccess) {
      await sendMetric('TransferCompleted', amount, req.instanceId, req.availabilityZone);
      logger.info(`Transfer completed - From: ${fromAccount}, To: ${toAccount}, Amount: ${amount}`);
    } else {
      await sendMetric('TransferFailed', 1, req.instanceId, req.availabilityZone);
      logger.warn(`Transfer failed - From: ${fromAccount}, To: ${toAccount}, Amount: ${amount}`);
    }

    res.status(isSuccess ? 200 : 400).json({
      transaction,
      message: isSuccess ? 'Transfer completed successfully' : 'Transfer failed',
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        processingTime: `${processingDelay}ms`
      }
    });
  } catch (error) {
    logger.error('Error processing transfer:', error);
    await sendMetric('TransactionErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to process transfer' });
  }
});

// 입출금 처리
router.post('/', async (req, res) => {
  try {
    const { error, value } = transactionSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ 
        error: 'Validation failed',
        details: error.details[0].message 
      });
    }

    const { accountNumber, type, amount, description } = value;

    // 데모용 처리 지연 시뮬레이션
    const processingDelay = Math.floor(Math.random() * 100) + 30;
    await new Promise(resolve => setTimeout(resolve, processingDelay));

    // 성공/실패 시뮬레이션 (99% 성공률)
    const isSuccess = Math.random() > 0.01;
    const status = isSuccess ? 'COMPLETED' : 'FAILED';

    const transaction = {
      id: transactions.length + 1,
      transactionId: `TXN${Date.now()}${String(transactions.length + 1).padStart(4, '0')}`,
      accountNumber,
      type,
      amount,
      description: description || (type === 'DEPOSIT' ? '입금' : '출금'),
      status,
      processingTime: processingDelay,
      createdAt: new Date().toISOString(),
      processedAt: new Date().toISOString(),
      failureReason: !isSuccess ? 'System error' : null
    };

    transactions.push(transaction);

    if (isSuccess) {
      await sendMetric(`${type}Completed`, amount, req.instanceId, req.availabilityZone);
      logger.info(`${type} completed - Account: ${accountNumber}, Amount: ${amount}`);
    } else {
      await sendMetric(`${type}Failed`, 1, req.instanceId, req.availabilityZone);
      logger.warn(`${type} failed - Account: ${accountNumber}, Amount: ${amount}`);
    }

    res.status(isSuccess ? 200 : 400).json({
      transaction,
      message: isSuccess ? `${type} completed successfully` : `${type} failed`,
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        processingTime: `${processingDelay}ms`
      }
    });
  } catch (error) {
    logger.error('Error processing transaction:', error);
    await sendMetric('TransactionErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to process transaction' });
  }
});

// 거래 통계
router.get('/stats/summary', async (req, res) => {
  try {
    const last24Hours = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const recentTransactions = transactions.filter(tx => 
      new Date(tx.createdAt) > last24Hours
    );

    const stats = {
      total: {
        transactions: transactions.length,
        amount: transactions.reduce((sum, tx) => sum + (tx.status === 'COMPLETED' ? tx.amount : 0), 0)
      },
      last24Hours: {
        transactions: recentTransactions.length,
        amount: recentTransactions.reduce((sum, tx) => sum + (tx.status === 'COMPLETED' ? tx.amount : 0), 0),
        successRate: recentTransactions.length > 0 
          ? (recentTransactions.filter(tx => tx.status === 'COMPLETED').length / recentTransactions.length * 100).toFixed(2)
          : 100
      },
      byType: {}
    };

    // 타입별 통계
    ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER'].forEach(type => {
      const typeTransactions = transactions.filter(tx => tx.type === type);
      stats.byType[type] = {
        count: typeTransactions.length,
        amount: typeTransactions.reduce((sum, tx) => sum + (tx.status === 'COMPLETED' ? tx.amount : 0), 0)
      };
    });

    await sendMetric('StatsViewed', 1, req.instanceId, req.availabilityZone);

    res.json({
      stats,
      meta: {
        instance: req.instanceId,
        zone: req.availabilityZone,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error retrieving transaction stats:', error);
    await sendMetric('TransactionErrors', 1, req.instanceId, req.availabilityZone);
    res.status(500).json({ error: 'Failed to retrieve transaction stats' });
  }
});

module.exports = router; 