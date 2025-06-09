/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    serverComponentsExternalPackages: ['@aws-sdk']
  },
  env: {
    AWS_REGION: process.env.AWS_REGION || 'us-east-1',
  }
}

module.exports = nextConfig 