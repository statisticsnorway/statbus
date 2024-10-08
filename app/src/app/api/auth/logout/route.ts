import { NextResponse } from 'next/server';
import { createApiClientAsync } from '@/utils/supabase/server';

export async function POST() {
  const client = await createApiClientAsync();
  await client.auth.signOut();
  return NextResponse.json({ success: true });
}
