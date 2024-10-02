import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/utils/supabase/server';

export async function GET(request : NextRequest) {
  const {client} = createClient(request);
  const { data: { session } } = await client.auth.getSession();

  if (session) {
    return NextResponse.json({ isAuthenticated: true });
  } else {
    return NextResponse.json({ isAuthenticated: false });
  }
}
