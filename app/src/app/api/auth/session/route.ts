import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function GET() {
  const supabaseClient = createClient();
  const { data: { session } } = await supabaseClient.auth.getSession();

  if (session) {
    return NextResponse.json({ isAuthenticated: true });
  } else {
    return NextResponse.json({ isAuthenticated: false });
  }
}
