import { NextResponse } from 'next/server';
import { FISClient, ListExperimentTemplatesCommand, ListExperimentsCommand } from '@aws-sdk/client-fis';

const fisClient = new FISClient({ 
  region: process.env.AWS_REGION || 'us-east-1' 
});

export async function GET() {
  try {
    // FIS 실험 템플릿 목록 조회
    const templatesCommand = new ListExperimentTemplatesCommand({});
    const templatesResponse = await fisClient.send(templatesCommand);

    // FIS 실험 실행 목록 조회  
    const experimentsCommand = new ListExperimentsCommand({});
    const experimentsResponse = await fisClient.send(experimentsCommand);

    // 데모용 실험 데이터 (실제 FIS가 없는 경우 대체)
    const mockExperiments = [
      {
        id: 'exp-az-a-stop-instances',
        name: 'AZ-A EC2 인스턴스 중단',
        status: 'STOPPED',
        duration: 600, // 10분
        targets: ['us-east-1a']
      },
      {
        id: 'exp-network-latency',
        name: '네트워크 지연 시뮬레이션',
        status: 'STOPPED',
        duration: 300, // 5분
        targets: ['ALB', 'EC2']
      },
      {
        id: 'exp-stress-cpu',
        name: 'CPU 부하 테스트',
        status: 'STOPPED',
        duration: 180, // 3분
        targets: ['EC2']
      }
    ];

    // 실제 FIS 데이터가 있으면 사용, 없으면 목 데이터 사용
    const experiments = experimentsResponse.experiments?.length 
      ? experimentsResponse.experiments.map(exp => ({
          id: exp.id || '',
          name: exp.experimentTemplateId || 'Unknown',
          status: exp.state?.status || 'STOPPED',
          startTime: exp.startTime?.toISOString(),
          endTime: exp.endTime?.toISOString(),
          duration: 600,
          targets: ['AWS Resources']
        }))
      : mockExperiments;

    return NextResponse.json({
      experiments,
      total: experiments.length,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Error fetching experiments:', error);
    
    // 에러 발생 시 목 데이터 반환
    const mockExperiments = [
      {
        id: 'exp-az-a-stop-instances',
        name: 'AZ-A EC2 인스턴스 중단',
        status: 'STOPPED',
        duration: 600,
        targets: ['us-east-1a']
      }
    ];

    return NextResponse.json({
      experiments: mockExperiments,
      total: mockExperiments.length,
      timestamp: new Date().toISOString(),
      warning: 'Using mock data due to AWS connection issue'
    });
  }
} 