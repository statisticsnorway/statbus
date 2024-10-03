import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/utils/supabase/server';

export async function GET(request : NextRequest) {
  const {client} = createClient(request);
  const session =
    client !== undefined ?
    (await client?.auth.getSession())?.data?.session :
    null;

  if (session) {
    return NextResponse.json({ isAuthenticated: true });
  } else {
    return NextResponse.json({ isAuthenticated: false });
  }
}
