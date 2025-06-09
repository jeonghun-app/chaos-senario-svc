const express = require('express');
const router = express.Router();
const logger = require('../utils/logger');
const { sendMetric } = require('../utils/metrics');

// 기본 인스턴스 정보 조회 (카오스 기능 제거)
router.get('/', async (req, res) => {
  try {
    const basicMetrics = {
      instance: {
        id: req.instanceId,
        zone: req.availabilityZone,
        uptime: process.uptime(),
        version: process.version,
        status: 'healthy'
      },
      timestamp: new Date().toISOString()
    };

    await sendMetric('BasicMetricsViewed', 1, req.instanceId, req.availabilityZone);

    res.json({
      metrics: basicMetrics,
      status: 'success'
    });
  } catch (error) {
    logger.error('Error retrieving basic metrics:', error);
    res.status(500).json({ error: 'Failed to retrieve metrics' });
  }
});

// 비즈니스 메트릭 요약 (카오스 기능 제거됨)
router.get('/business-summary', async (req, res) => {
  try {
    const summary = {
      service: 'Bank Demo WAS',
      businessMetrics: {
        totalRequests: process.env.TOTAL_REQUESTS || 0,
        successfulTransactions: process.env.SUCCESSFUL_TRANSACTIONS || 0,
        activeAccounts: process.env.ACTIVE_ACCOUNTS || 0
      },
      instance: {
        id: req.instanceId,
        zone: req.availabilityZone,
        uptime: process.uptime()
      },
      timestamp: new Date().toISOString()
    };
    
    await sendMetric('BusinessSummaryViewed', 1, req.instanceId, req.availabilityZone);
    
    res.json({
      summary,
      status: 'success'
    });
  } catch (error) {
    logger.error('Error retrieving business summary:', error);
    res.status(500).json({ error: 'Failed to retrieve business summary' });
  }
});

module.exports = router; 