// src/utils/supabase/middleware.ts
"use server";

import { createClient } from '@/utils/supabase/server'
import { type NextRequest } from 'next/server'

export async function updateSession(request: NextRequest) {
  const { client, response } = createClient(request);

  // refreshing the auth token
  var {data: {session}} = await client.auth.getSession();

  return { client, response, session };
}
