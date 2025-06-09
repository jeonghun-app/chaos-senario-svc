const express = require('express');
const router = express.Router();
const logger = require('../utils/logger');

// Simple health check for ALB
router.get('/', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    instance: req.instanceId,
    zone: req.availabilityZone,
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    version: '1.0.0'
  });
});

// Detailed health check
router.get('/detailed', (req, res) => {
  const healthData = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    instance: req.instanceId,
    zone: req.availabilityZone,
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    cpu: process.cpuUsage(),
    version: '1.0.0',
    node_version: process.version,
    platform: process.platform,
    arch: process.arch,
    environment: process.env.NODE_ENV || 'development',
    checks: {
      database: 'healthy', // 실제 환경에서는 DB 연결 체크
      external_apis: 'healthy',
      disk_space: 'healthy'
    }
  };

  // 메모리 사용량이 너무 높으면 degraded 상태로 표시
  const memoryUsagePercent = (healthData.memory.heapUsed / healthData.memory.heapTotal) * 100;
  if (memoryUsagePercent > 90) {
    healthData.status = 'degraded';
    healthData.warnings = ['High memory usage'];
  }

  logger.info(`Health check - Status: ${healthData.status}, Memory: ${memoryUsagePercent.toFixed(2)}%`);

  res.status(healthData.status === 'healthy' ? 200 : 503).json(healthData);
});

// Readiness probe
router.get('/ready', (req, res) => {
  // 애플리케이션이 요청을 받을 준비가 되었는지 확인
  const isReady = process.uptime() > 5; // 5초 후에 ready 상태
  
  if (isReady) {
    res.status(200).json({
      status: 'ready',
      timestamp: new Date().toISOString(),
      instance: req.instanceId,
      zone: req.availabilityZone
    });
  } else {
    res.status(503).json({
      status: 'not_ready',
      timestamp: new Date().toISOString(),
      instance: req.instanceId,
      zone: req.availabilityZone,
      message: 'Application is still starting up'
    });
  }
});

// Liveness probe
router.get('/live', (req, res) => {
  // 애플리케이션이 살아있는지 확인
  res.status(200).json({
    status: 'alive',
    timestamp: new Date().toISOString(),
    instance: req.instanceId,
    zone: req.availabilityZone,
    uptime: process.uptime()
  });
});

module.exports = router; 