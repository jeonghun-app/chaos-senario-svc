'use client';

import { useState, useEffect } from 'react';

interface Experiment {
  id: string;
  name: string;
  status: 'RUNNING' | 'STOPPED' | 'COMPLETED' | 'FAILED';
  startTime?: string;
  endTime?: string;
  duration: number;
  targets: string[];
}

interface MetricData {
  timestamp: string;
  value: number;
  unit: string;
}

interface ServiceMetrics {
  responseTime: MetricData[];
  errorRate: MetricData[];
  requestCount: MetricData[];
  instanceCount: number;
  healthyInstances: number;
}

export default function ChaosMonitoringDashboard() {
  const [experiments, setExperiments] = useState<Experiment[]>([]);
  const [metrics, setMetrics] = useState<ServiceMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [autoRefresh, setAutoRefresh] = useState(true);

  useEffect(() => {
    fetchData();
    
    if (autoRefresh) {
      const interval = setInterval(fetchData, 30000); // 30초마다 갱신
      return () => clearInterval(interval);
    }
  }, [autoRefresh]);

  const fetchData = async () => {
    try {
      const [experimentsRes, metricsRes] = await Promise.all([
        fetch('/api/experiments'),
        fetch('/api/metrics/service-status')
      ]);

      if (experimentsRes.ok) {
        const experimentsData = await experimentsRes.json();
        setExperiments(experimentsData.experiments || []);
      }

      if (metricsRes.ok) {
        const metricsData = await metricsRes.json();
        setMetrics(metricsData.metrics);
      }
    } catch (error) {
      console.error('Error fetching data:', error);
    } finally {
      setLoading(false);
    }
  };

  const startExperiment = async (experimentId: string) => {
    try {
      const response = await fetch(`/api/experiments/${experimentId}/start`, {
        method: 'POST'
      });
      
      if (response.ok) {
        fetchData(); // 데이터 새로고침
      }
    } catch (error) {
      console.error('Error starting experiment:', error);
    }
  };

  const stopExperiment = async (experimentId: string) => {
    try {
      const response = await fetch(`/api/experiments/${experimentId}/stop`, {
        method: 'POST'
      });
      
      if (response.ok) {
        fetchData(); // 데이터 새로고침
      }
    } catch (error) {
      console.error('Error stopping experiment:', error);
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'RUNNING':
        return <span className="text-yellow-500">🔄</span>;
      case 'COMPLETED':
        return <span className="text-green-500">✅</span>;
      case 'FAILED':
        return <span className="text-red-500">❌</span>;
      default:
        return <span className="text-gray-500">⏰</span>;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'RUNNING':
        return 'bg-yellow-100 text-yellow-800';
      case 'COMPLETED':
        return 'bg-green-100 text-green-800';
      case 'FAILED':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="text-4xl animate-spin">🔄</div>
          <p className="mt-4 text-gray-600">모니터링 시스템 로딩 중...</p>
        </div>
      </div>
    );
  }

  const currentExperiment = experiments.find(exp => exp.status === 'RUNNING');
  const serviceHealth = metrics?.healthyInstances === metrics?.instanceCount ? 'HEALTHY' : 'DEGRADED';

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <span className="text-2xl mr-3">⚠️</span>
              <h1 className="text-2xl font-bold text-gray-900">Chaos Engineering Monitor</h1>
            </div>
            <div className="flex items-center space-x-4">
              <button
                onClick={() => setAutoRefresh(!autoRefresh)}
                className={`px-3 py-2 rounded-md text-sm font-medium ${
                  autoRefresh 
                    ? 'bg-green-100 text-green-800' 
                    : 'bg-gray-100 text-gray-800'
                }`}
              >
                {autoRefresh ? '실시간 갱신 ON' : '실시간 갱신 OFF'}
              </button>
              <button
                onClick={fetchData}
                className="px-3 py-2 bg-blue-600 text-white rounded-md text-sm font-medium hover:bg-blue-700"
              >
                새로고침
              </button>
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Service Status Overview */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className={`p-2 rounded-md ${serviceHealth === 'HEALTHY' ? 'bg-green-100' : 'bg-red-100'}`}>
                {serviceHealth === 'HEALTHY' ? 
                  <span className="text-green-600 text-xl">✅</span> :
                  <span className="text-red-600 text-xl">❌</span>
                }
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">서비스 상태</p>
                <p className={`text-lg font-semibold ${serviceHealth === 'HEALTHY' ? 'text-green-600' : 'text-red-600'}`}>
                  {serviceHealth === 'HEALTHY' ? '정상' : '장애'}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className="p-2 bg-blue-100 rounded-md">
                <span className="text-blue-600 text-xl">📊</span>
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">활성 인스턴스</p>
                <p className="text-lg font-semibold text-gray-900">
                  {metrics?.healthyInstances || 0} / {metrics?.instanceCount || 0}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className={`p-2 rounded-md ${currentExperiment ? 'bg-yellow-100' : 'bg-gray-100'}`}>
                {currentExperiment ? 
                  <span className="text-yellow-600 text-xl animate-spin">🔄</span> :
                  <span className="text-gray-600 text-xl">⏰</span>
                }
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">실험 상태</p>
                <p className="text-lg font-semibold text-gray-900">
                  {currentExperiment ? '실행 중' : '대기 중'}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className="p-2 bg-purple-100 rounded-md">
                <span className="text-purple-600 text-xl">⏰</span>
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">RTO 목표</p>
                <p className="text-lg font-semibold text-gray-900">≤ 10분</p>
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* 실험 관리 */}
          <div className="bg-white rounded-lg shadow">
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-lg font-semibold text-gray-900">Chaos 실험 관리</h2>
            </div>
            <div className="p-6">
              <div className="space-y-4">
                {experiments.length > 0 ? (
                  experiments.map((experiment) => (
                    <div key={experiment.id} className="border border-gray-200 rounded-lg p-4">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center">
                          {getStatusIcon(experiment.status)}
                          <div className="ml-3">
                            <h3 className="text-sm font-medium text-gray-900">{experiment.name}</h3>
                            <p className="text-xs text-gray-500">대상: {experiment.targets.join(', ')}</p>
                          </div>
                        </div>
                        <div className="flex items-center space-x-2">
                          <span className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusColor(experiment.status)}`}>
                            {experiment.status}
                          </span>
                          {experiment.status === 'STOPPED' && (
                            <button
                              onClick={() => startExperiment(experiment.id)}
                              className="p-1 text-green-600 hover:text-green-700"
                            >
                              <span>▶️</span>
                            </button>
                          )}
                          {experiment.status === 'RUNNING' && (
                            <button
                              onClick={() => stopExperiment(experiment.id)}
                              className="p-1 text-red-600 hover:text-red-700"
                            >
                              <span>⏹️</span>
                            </button>
                          )}
                        </div>
                      </div>
                      {experiment.startTime && (
                        <div className="mt-2 text-xs text-gray-500">
                          시작: {new Date(experiment.startTime).toLocaleString('ko-KR')}
                        </div>
                      )}
                    </div>
                  ))
                ) : (
                  <div className="text-center py-8 text-gray-500">
                    <span className="text-4xl text-gray-300">⚠️</span>
                    <p>등록된 실험이 없습니다.</p>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* 실시간 메트릭 */}
          <div className="bg-white rounded-lg shadow">
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-lg font-semibold text-gray-900">실시간 메트릭</h2>
            </div>
            <div className="p-6">
              <div className="space-y-6">
                <div>
                  <h3 className="text-sm font-medium text-gray-700 mb-2">응답 시간 (P95)</h3>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <p className="text-2xl font-bold text-gray-900">
                      {metrics?.responseTime?.[0]?.value?.toFixed(2) || '0'} ms
                    </p>
                    <p className="text-sm text-gray-500">목표: ≤ 2× Baseline</p>
                  </div>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-gray-700 mb-2">5XX 에러율</h3>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <p className="text-2xl font-bold text-gray-900">
                      {metrics?.errorRate?.[0]?.value?.toFixed(2) || '0'}%
                    </p>
                    <p className="text-sm text-gray-500">목표: ≤ 5%</p>
                  </div>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-gray-700 mb-2">요청 수 (1분)</h3>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <p className="text-2xl font-bold text-gray-900">
                      {metrics?.requestCount?.[0]?.value || '0'}
                    </p>
                    <p className="text-sm text-gray-500">실시간 트래픽</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* 실험 시나리오 */}
        <div className="mt-8 bg-white rounded-lg shadow">
          <div className="px-6 py-4 border-b border-gray-200">
            <h2 className="text-lg font-semibold text-gray-900">10단계 데모 시나리오</h2>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
              {[
                'T-15min: 베이스라인 측정',
                'T-10min: 실험 준비',
                'T-5min: 모니터링 확인',
                'T-0min: Chaos 실험 시작',
                'T+2min: AZ-A 인스턴스 중단',
                'T+5min: 트래픽 재분산',
                'T+8min: 복구 감지',
                'T+10min: 실험 종료',
                'T+15min: 결과 분석',
                'T+20min: 보고서 생성'
              ].map((step, index) => (
                <div key={index} className="bg-gray-50 rounded-lg p-3 text-center">
                  <div className="text-sm font-medium text-gray-900">{step.split(':')[0]}</div>
                  <div className="text-xs text-gray-600 mt-1">{step.split(':')[1]}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
} 