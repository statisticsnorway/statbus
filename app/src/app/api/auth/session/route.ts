import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/utils/supabase/server';

export async function GET(request : NextRequest) {
  const client = await createSupabaseServerClient();
  const session = (await client?.auth.getSession())?.data?.session;

  if (session) {
    return NextResponse.json({ isAuthenticated: true });
  } else {
    return NextResponse.json({ isAuthenticated: false });
  }
}
