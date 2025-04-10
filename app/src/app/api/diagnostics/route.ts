import { NextRequest, NextResponse } from 'next/server';
import { runNetworkDiagnostics } from '@/utils/network-diagnostics';

/**
 * API endpoint for network diagnostics
 * This endpoint runs connectivity tests to various services and returns the results
 * It's useful for troubleshooting connectivity issues in different environments
 */
export async function GET(request: NextRequest) {
  try {
    const diagnostics = await runNetworkDiagnostics();
    
    return NextResponse.json({
      success: true,
      diagnostics
    });
  } catch (error) {
    console.error('Error running network diagnostics:', error);
    
    return NextResponse.json({
      success: false,
      error: error instanceof Error ? error.message : String(error)
    }, { status: 500 });
  }
}
