const AWS = require('aws-sdk');
const logger = require('./logger');
const config = require('../config/config');

// CloudWatch 인스턴스 생성
const cloudwatch = new AWS.CloudWatch({
  region: config.aws.region
});

/**
 * CloudWatch 사용자 정의 메트릭 전송
 * @param {string} metricName - 메트릭 이름
 * @param {number} value - 메트릭 값
 * @param {string} instanceId - EC2 인스턴스 ID
 * @param {string} availabilityZone - 가용영역
 * @param {string} unit - 메트릭 단위 (기본값: Count)
 */
async function sendMetric(metricName, value, instanceId, availabilityZone, unit = 'Count') {
  if (!config.cloudwatch.enabled) {
    logger.debug(`CloudWatch disabled - Metric: ${metricName}, Value: ${value}`);
    return;
  }

  const params = {
    Namespace: config.cloudwatch.namespace,
    MetricData: [{
      MetricName: metricName,
      Value: value,
      Unit: unit,
      Timestamp: new Date(),
      Dimensions: [{
        Name: 'InstanceId',
        Value: instanceId
      }, {
        Name: 'AvailabilityZone',
        Value: availabilityZone
      }, {
        Name: 'Service',
        Value: 'BankDemoWAS'
      }]
    }]
  };

  try {
    await cloudwatch.putMetricData(params).promise();
    logger.debug(`CloudWatch metric sent - ${metricName}: ${value} ${unit}`);
  } catch (error) {
    logger.error('Failed to send CloudWatch metric:', {
      metricName,
      value,
      error: error.message
    });
  }
}

/**
 * 여러 메트릭을 한 번에 전송
 * @param {Array} metrics - 메트릭 배열
 * @param {string} instanceId - EC2 인스턴스 ID
 * @param {string} availabilityZone - 가용영역
 */
async function sendBatchMetrics(metrics, instanceId, availabilityZone) {
  if (!config.cloudwatch.enabled || !metrics.length) {
    return;
  }

  const metricData = metrics.map(metric => ({
    MetricName: metric.name,
    Value: metric.value,
    Unit: metric.unit || 'Count',
    Timestamp: new Date(),
    Dimensions: [{
      Name: 'InstanceId',
      Value: instanceId
    }, {
      Name: 'AvailabilityZone',
      Value: availabilityZone
    }, {
      Name: 'Service',
      Value: 'BankDemoWAS'
    }]
  }));

  const params = {
    Namespace: config.cloudwatch.namespace,
    MetricData: metricData
  };

  try {
    await cloudwatch.putMetricData(params).promise();
    logger.debug(`CloudWatch batch metrics sent - Count: ${metrics.length}`);
  } catch (error) {
    logger.error('Failed to send CloudWatch batch metrics:', {
      count: metrics.length,
      error: error.message
    });
  }
}

/**
 * 응답 시간 메트릭 미들웨어
 */
function responseTimeMiddleware() {
  return (req, res, next) => {
    const startTime = Date.now();
    
    res.on('finish', async () => {
      const responseTime = Date.now() - startTime;
      const statusCode = res.statusCode;
      
      // 응답 시간 메트릭
      await sendMetric('ResponseTime', responseTime, req.instanceId, req.availabilityZone, 'Milliseconds');
      
      // HTTP 상태 코드별 메트릭
      if (statusCode >= 200 && statusCode < 300) {
        await sendMetric('HTTP2XX', 1, req.instanceId, req.availabilityZone);
      } else if (statusCode >= 300 && statusCode < 400) {
        await sendMetric('HTTP3XX', 1, req.instanceId, req.availabilityZone);
      } else if (statusCode >= 400 && statusCode < 500) {
        await sendMetric('HTTP4XX', 1, req.instanceId, req.availabilityZone);
      } else if (statusCode >= 500) {
        await sendMetric('HTTP5XX', 1, req.instanceId, req.availabilityZone);
      }
      
      // 요청 수 메트릭
      await sendMetric('RequestCount', 1, req.instanceId, req.availabilityZone);
      
      logger.debug(`Request processed - ${req.method} ${req.path} - ${statusCode} - ${responseTime}ms`);
    });
    
    next();
  };
}

/**
 * 시스템 메트릭 수집 및 전송
 * @param {string} instanceId - EC2 인스턴스 ID
 * @param {string} availabilityZone - 가용영역
 */
async function sendSystemMetrics(instanceId, availabilityZone) {
  try {
    const memoryUsage = process.memoryUsage();
    const cpuUsage = process.cpuUsage();
    
    const metrics = [
      {
        name: 'MemoryUsed',
        value: memoryUsage.heapUsed,
        unit: 'Bytes'
      },
      {
        name: 'MemoryTotal',
        value: memoryUsage.heapTotal,
        unit: 'Bytes'
      },
      {
        name: 'MemoryExternal',
        value: memoryUsage.external,
        unit: 'Bytes'
      },
      {
        name: 'ProcessUptime',
        value: process.uptime(),
        unit: 'Seconds'
      }
    ];
    
    await sendBatchMetrics(metrics, instanceId, availabilityZone);
  } catch (error) {
    logger.error('Failed to send system metrics:', error);
  }
}

/**
 * 정기적으로 기본 메트릭 전송 (10분마다) 
 */
function startBasicMetricsScheduler() {
  const instanceId = config.aws.instanceId;
  const availabilityZone = config.aws.availabilityZone;
  
  setInterval(async () => {
    // 기본적인 비즈니스 메트릭만 전송
    const basicMetrics = [
      {
        name: 'ServiceHealthy',
        value: 1,
        unit: 'Count'
      },
      {
        name: 'ProcessUptime',
        value: process.uptime(),
        unit: 'Seconds'
      }
    ];
    
    await sendBatchMetrics(basicMetrics, instanceId, availabilityZone);
  }, 10 * 60 * 1000); // 10분마다
  
  logger.info('Basic metrics scheduler started');
}

module.exports = {
  sendMetric,
  sendBatchMetrics,
  responseTimeMiddleware,
  sendSystemMetrics,
  startBasicMetricsScheduler
}; 