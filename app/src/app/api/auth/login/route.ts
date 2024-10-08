import { NextResponse } from 'next/server';
import { createApiClientAsync } from '@/utils/supabase/server';
import { createServerLogger } from '@/lib/server-logger';

export async function POST(request: Request) {
  const { email, password } = await request.json();
  const client = await createApiClientAsync();

  const { error } = await client.auth.signInWithPassword({
    email,
    password,
  });

  const logger = await createServerLogger();

  if (error) {
    logger.error({ ...error, email }, `Login failed`);
    return NextResponse.json({ error: error.message }, { status: 401 });
  }

  logger.info("Login successful");
  return NextResponse.json({ success: true });
}
