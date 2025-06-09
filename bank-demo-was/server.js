const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const AWS = require('aws-sdk');
const logger = require('./utils/logger');
const config = require('./config/config');

// Route imports  
const accountRoutes = require('./routes/accounts');
const transactionRoutes = require('./routes/transactions');
const healthRoutes = require('./routes/health');
const metricsRoutes = require('./routes/metrics');

const app = express();
const PORT = process.env.PORT || 8080;

// AWS CloudWatch setup for metrics
const cloudwatch = new AWS.CloudWatch({
  region: process.env.AWS_REGION || 'ap-northeast-2'
});

// Security middleware
app.use(helmet());
app.use(compression());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // limit each IP to 1000 requests per windowMs
  message: 'Too many requests from this IP, please try again later.'
});
app.use(limiter);

// CORS configuration
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true
}));

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Logging middleware
app.use(morgan('combined', {
  stream: { write: message => logger.info(message.trim()) }
}));

// Custom middleware to add instance metadata
app.use((req, res, next) => {
  req.instanceId = process.env.INSTANCE_ID || 'local-dev';
  req.availabilityZone = process.env.AWS_AVAILABILITY_ZONE || 'local';
  next();
});

// Routes
app.use('/api/health', healthRoutes);
app.use('/api/accounts', accountRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/metrics', metricsRoutes);

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'Bank Demo WAS',
    version: '1.0.0',
    instance: req.instanceId,
    zone: req.availabilityZone,
    timestamp: new Date().toISOString(),
    status: 'healthy'
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  
  // Send CloudWatch metric for errors
  const params = {
    Namespace: 'BankDemo/WAS',
    MetricData: [{
      MetricName: 'ApplicationErrors',
      Value: 1,
      Unit: 'Count',
      Dimensions: [{
        Name: 'InstanceId',
        Value: req.instanceId
      }, {
        Name: 'AvailabilityZone',
        Value: req.availabilityZone
      }]
    }]
  };
  
  cloudwatch.putMetricData(params, (cloudwatchErr) => {
    if (cloudwatchErr) {
      logger.error('Failed to send CloudWatch metric:', cloudwatchErr);
    }
  });

  res.status(500).json({
    error: 'Internal Server Error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong',
    instance: req.instanceId,
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Route ${req.originalUrl} not found`,
    instance: req.instanceId,
    timestamp: new Date().toISOString()
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  server.close(() => {
    logger.info('Process terminated');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  server.close(() => {
    logger.info('Process terminated');
    process.exit(0);
  });
});

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info(`Bank Demo WAS server running on port ${PORT}`);
  logger.info(`Instance ID: ${process.env.INSTANCE_ID || 'local-dev'}`);
  logger.info(`Availability Zone: ${process.env.AWS_AVAILABILITY_ZONE || 'local'}`);
});

module.exports = app; 