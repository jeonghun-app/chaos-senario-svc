'use client';

import { useState, useEffect } from 'react';
import { Button, Card, Alert } from 'flowbite-react';
import { 
  BanknotesIcon, 
  CreditCardIcon, 
  ArrowsRightLeftIcon, 
  DocumentTextIcon,
  ChartBarIcon,
  ShieldCheckIcon
} from '@heroicons/react/24/outline';

interface Account {
  id: number;
  accountNumber: string;
  accountName: string;
  customerName: string;
  accountType: string;
  balance: number;
  status: string;
}

interface Transaction {
  id: number;
  transactionId: string;
  type: string;
  amount: number;
  description: string;
  createdAt: string;
}

export default function HomePage() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [recentTransactions, setRecentTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchAccountData();
    fetchRecentTransactions();
  }, []);

  const fetchAccountData = async () => {
    try {
      const response = await fetch('/api/accounts?limit=3');
      if (!response.ok) throw new Error('계좌 정보를 불러올 수 없습니다.');
      const data = await response.json();
      setAccounts(data.accounts || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : '오류가 발생했습니다.');
    }
  };

  const fetchRecentTransactions = async () => {
    try {
      const response = await fetch('/api/transactions?limit=5');
      if (!response.ok) throw new Error('거래 내역을 불러올 수 없습니다.');
      const data = await response.json();
      setRecentTransactions(data.transactions || []);
    } catch (err) {
      console.error('거래 내역 조회 실패:', err);
    } finally {
      setLoading(false);
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('ko-KR', {
      style: 'currency',
      currency: 'KRW'
    }).format(amount);
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('ko-KR', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const getAccountTypeLabel = (type: string) => {
    const types: { [key: string]: string } = {
      'CHECKING': '입출금통장',
      'SAVINGS': '적금',
      'DEPOSIT': '예금'
    };
    return types[type] || type;
  };

  const getTransactionTypeLabel = (type: string) => {
    const types: { [key: string]: string } = {
      'DEPOSIT': '입금',
      'WITHDRAWAL': '출금',
      'TRANSFER': '이체'
    };
    return types[type] || type;
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600">로딩 중...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <BanknotesIcon className="h-8 w-8 text-blue-600 mr-3" />
              <h1 className="text-2xl font-bold text-gray-900">AWS Demo Bank</h1>
            </div>
            <div className="flex items-center space-x-4">
              <span className="text-sm text-gray-600">안녕하세요, 고객님</span>
              <Button color="blue" size="sm">로그아웃</Button>
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {error && (
          <Alert color="failure" className="mb-6">
            <span className="font-medium">오류!</span> {error}
          </Alert>
        )}

        {/* Quick Actions */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          <Button className="h-20 flex flex-col items-center justify-center" color="blue">
            <ArrowsRightLeftIcon className="h-6 w-6 mb-2" />
            <span>계좌이체</span>
          </Button>
          <Button className="h-20 flex flex-col items-center justify-center" color="gray">
            <DocumentTextIcon className="h-6 w-6 mb-2" />
            <span>거래내역</span>
          </Button>
          <Button className="h-20 flex flex-col items-center justify-center" color="gray">
            <CreditCardIcon className="h-6 w-6 mb-2" />
            <span>카드관리</span>
          </Button>
          <Button className="h-20 flex flex-col items-center justify-center" color="gray">
            <ChartBarIcon className="h-6 w-6 mb-2" />
            <span>자산현황</span>
          </Button>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* 내 계좌 */}
          <Card>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-gray-900">내 계좌</h2>
              <Button color="light" size="xs">전체보기</Button>
            </div>
            
            <div className="space-y-4">
              {accounts.length > 0 ? (
                accounts.map((account) => (
                  <div key={account.id} className="p-4 bg-gray-50 rounded-lg">
                    <div className="flex justify-between items-start">
                      <div>
                        <h3 className="font-medium text-gray-900">{account.accountName}</h3>
                        <p className="text-sm text-gray-600">{account.accountNumber}</p>
                        <p className="text-xs text-gray-500">{getAccountTypeLabel(account.accountType)}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-lg font-semibold text-gray-900">
                          {formatCurrency(account.balance)}
                        </p>
                        <p className={`text-xs ${account.status === 'ACTIVE' ? 'text-green-600' : 'text-red-600'}`}>
                          {account.status === 'ACTIVE' ? '정상' : '비활성'}
                        </p>
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-8 text-gray-500">
                  <CreditCardIcon className="h-12 w-12 mx-auto mb-4 text-gray-300" />
                  <p>등록된 계좌가 없습니다.</p>
                </div>
              )}
            </div>
          </Card>

          {/* 최근 거래 내역 */}
          <Card>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-gray-900">최근 거래</h2>
              <Button color="light" size="xs">전체보기</Button>
            </div>
            
            <div className="space-y-3">
              {recentTransactions.length > 0 ? (
                recentTransactions.map((transaction) => (
                  <div key={transaction.id} className="flex justify-between items-center py-3 border-b border-gray-100 last:border-b-0">
                    <div>
                      <p className="font-medium text-gray-900">{transaction.description}</p>
                      <p className="text-sm text-gray-600">{getTransactionTypeLabel(transaction.type)}</p>
                      <p className="text-xs text-gray-500">{formatDate(transaction.createdAt)}</p>
                    </div>
                    <div className="text-right">
                      <p className={`font-semibold ${
                        transaction.type === 'DEPOSIT' ? 'text-blue-600' : 'text-red-600'
                      }`}>
                        {transaction.type === 'DEPOSIT' ? '+' : '-'}
                        {formatCurrency(transaction.amount)}
                      </p>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-8 text-gray-500">
                  <DocumentTextIcon className="h-12 w-12 mx-auto mb-4 text-gray-300" />
                  <p>최근 거래 내역이 없습니다.</p>
                </div>
              )}
            </div>
          </Card>
        </div>

        {/* 공지사항 & 보안 */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mt-8">
          <Card>
            <h2 className="text-lg font-semibold text-gray-900 mb-4">공지사항</h2>
            <div className="space-y-3">
              <div className="p-3 bg-blue-50 rounded-lg">
                <h3 className="font-medium text-blue-900">시스템 점검 안내</h3>
                <p className="text-sm text-blue-700">2024년 1월 15일 새벽 2시-4시 시스템 점검이 예정되어 있습니다.</p>
              </div>
              <div className="p-3 bg-yellow-50 rounded-lg">
                <h3 className="font-medium text-yellow-900">보안 강화 안내</h3>
                <p className="text-sm text-yellow-700">추가 인증 수단 설정을 권장합니다.</p>
              </div>
            </div>
          </Card>

          <Card>
            <h2 className="text-lg font-semibold text-gray-900 mb-4">보안센터</h2>
            <div className="space-y-4">
              <div className="flex items-center">
                <ShieldCheckIcon className="h-5 w-5 text-green-600 mr-3" />
                <span className="text-sm text-gray-700">보안등급: 우수</span>
              </div>
              <div className="text-sm text-gray-600">
                <p>• 최근 로그인: 2024.01.10 14:30</p>
                <p>• 비밀번호 변경: 2024.01.01</p>
                <p>• 보안카드 등록: 완료</p>
              </div>
              <Button color="blue" size="sm" className="w-full">
                보안설정 관리
              </Button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
