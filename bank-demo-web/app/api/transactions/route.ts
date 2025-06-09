import { NextRequest, NextResponse } from 'next/server';

const WAS_BASE_URL = process.env.WAS_BASE_URL || 'http://localhost:8080';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const limit = searchParams.get('limit') || '10';
    const accountId = searchParams.get('accountId');
    
    let url = `${WAS_BASE_URL}/api/transactions?limit=${limit}`;
    if (accountId) {
      url += `&accountId=${accountId}`;
    }
    
    // WAS API 호출
    const response = await fetch(url, {
      headers: {
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`WAS API error: ${response.status}`);
    }

    const data = await response.json();
    
    return NextResponse.json(data);
  } catch (error) {
    console.error('Transaction API error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch transactions' },
      { status: 500 }
    );
  }
} 