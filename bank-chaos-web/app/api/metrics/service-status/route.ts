import { NextResponse } from 'next/server';
import { CloudWatchClient, GetMetricStatisticsCommand } from '@aws-sdk/client-cloudwatch';

const cloudWatchClient = new CloudWatchClient({ 
  region: process.env.AWS_REGION || 'us-east-1' 
});

export async function GET() {
  try {
    const endTime = new Date();
    const startTime = new Date(endTime.getTime() - 15 * 60 * 1000); // 15분 전

    // 응답 시간 메트릭 조회
    const responseTimeCommand = new GetMetricStatisticsCommand({
      Namespace: 'AWS/ApplicationELB',
      MetricName: 'TargetResponseTime',
      Dimensions: [
        {
          Name: 'LoadBalancer',
          Value: 'app/bank-demo-alb/*'
        }
      ],
      StartTime: startTime,
      EndTime: endTime,
      Period: 300, // 5분 간격
      Statistics: ['Average']
    });

    // 에러율 메트릭 조회
    const errorRateCommand = new GetMetricStatisticsCommand({
      Namespace: 'AWS/ApplicationELB',
      MetricName: 'HTTPCode_Target_5XX_Count',
      Dimensions: [
        {
          Name: 'LoadBalancer',
          Value: 'app/bank-demo-alb/*'
        }
      ],
      StartTime: startTime,
      EndTime: endTime,
      Period: 300,
      Statistics: ['Sum']
    });

    // 요청 수 메트릭 조회
    const requestCountCommand = new GetMetricStatisticsCommand({
      Namespace: 'AWS/ApplicationELB',
      MetricName: 'RequestCount',
      Dimensions: [
        {
          Name: 'LoadBalancer', 
          Value: 'app/bank-demo-alb/*'
        }
      ],
      StartTime: startTime,
      EndTime: endTime,
      Period: 300,
      Statistics: ['Sum']
    });

    const [responseTimeResult, errorRateResult, requestCountResult] = await Promise.allSettled([
      cloudWatchClient.send(responseTimeCommand),
      cloudWatchClient.send(errorRateCommand),
      cloudWatchClient.send(requestCountCommand)
    ]);

    // 결과 처리
    const responseTimeData = responseTimeResult.status === 'fulfilled' 
      ? responseTimeResult.value.Datapoints?.map(dp => ({
          timestamp: dp.Timestamp?.toISOString() || '',
          value: dp.Average || 0,
          unit: 'Milliseconds'
        })) || []
      : [];

    const errorRateData = errorRateResult.status === 'fulfilled'
      ? errorRateResult.value.Datapoints?.map(dp => ({
          timestamp: dp.Timestamp?.toISOString() || '',
          value: dp.Sum || 0,
          unit: 'Count'
        })) || []
      : [];

    const requestCountData = requestCountResult.status === 'fulfilled'
      ? requestCountResult.value.Datapoints?.map(dp => ({
          timestamp: dp.Timestamp?.toISOString() || '',
          value: dp.Sum || 0,
          unit: 'Count'
        })) || []
      : [];

    // 목 데이터 (AWS 연결이 안 될 경우)
    const mockMetrics = {
      responseTime: [
        {
          timestamp: new Date().toISOString(),
          value: Math.random() * 200 + 50, // 50-250ms
          unit: 'Milliseconds'
        }
      ],
      errorRate: [
        {
          timestamp: new Date().toISOString(),
          value: Math.random() * 2, // 0-2%
          unit: 'Percent'
        }
      ],
      requestCount: [
        {
          timestamp: new Date().toISOString(),
          value: Math.floor(Math.random() * 1000) + 100, // 100-1100 requests
          unit: 'Count'
        }
      ],
      instanceCount: 3,
      healthyInstances: Math.floor(Math.random() * 3) + 1 // 1-3
    };

    // 실제 데이터가 있으면 사용, 없으면 목 데이터
    const metrics = {
      responseTime: responseTimeData.length ? responseTimeData : mockMetrics.responseTime,
      errorRate: errorRateData.length ? errorRateData : mockMetrics.errorRate,
      requestCount: requestCountData.length ? requestCountData : mockMetrics.requestCount,
      instanceCount: mockMetrics.instanceCount,
      healthyInstances: mockMetrics.healthyInstances
    };

    return NextResponse.json({
      metrics,
      timestamp: new Date().toISOString(),
      period: '15min'
    });

  } catch (error) {
    console.error('Error fetching CloudWatch metrics:', error);
    
    // 에러 시 목 데이터 반환
    const mockMetrics = {
      responseTime: [
        {
          timestamp: new Date().toISOString(),
          value: 120.5,
          unit: 'Milliseconds'
        }
      ],
      errorRate: [
        {
          timestamp: new Date().toISOString(),
          value: 1.2,
          unit: 'Percent'
        }
      ],
      requestCount: [
        {
          timestamp: new Date().toISOString(),
          value: 456,
          unit: 'Count'
        }
      ],
      instanceCount: 3,
      healthyInstances: 3
    };

    return NextResponse.json({
      metrics: mockMetrics,
      timestamp: new Date().toISOString(),
      period: '15min',
      warning: 'Using mock data due to CloudWatch connection issue'
    });
  }
} 