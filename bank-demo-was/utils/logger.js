const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.printf(({ timestamp, level, message, stack, ...meta }) => {
      const instanceId = process.env.INSTANCE_ID || 'local-dev';
      const zone = process.env.AWS_AVAILABILITY_ZONE || 'local';
      
      let logMessage = `${timestamp} [${level.toUpperCase()}] [${instanceId}] [${zone}] ${message}`;
      
      if (Object.keys(meta).length > 0) {
        logMessage += ` ${JSON.stringify(meta)}`;
      }
      
      if (stack) {
        logMessage += `\n${stack}`;
      }
      
      return logMessage;
    })
  ),
  transports: [
    new winston.transports.Console({
      colorize: true
    }),
    new winston.transports.File({
      filename: 'logs/error.log',
      level: 'error'
    }),
    new winston.transports.File({
      filename: 'logs/combined.log'
    })
  ]
});

// CloudWatch Logs integration in production
if (process.env.NODE_ENV === 'production') {
  // Add CloudWatch transport if needed
  logger.info('Logger configured for production environment');
}

module.exports = logger; 