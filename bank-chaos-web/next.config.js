/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    serverComponentsExternalPackages: ['@aws-sdk']
  },
  env: {
    AWS_REGION: process.env.AWS_REGION || 'us-east-1',
  },
  // Development mode 설정
  ...(process.env.NODE_ENV === 'development' && {
    allowedDevOrigins: ['*'],
  }),
}

module.exports = nextConfig 