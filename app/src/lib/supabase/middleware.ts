"use server";
import { createServerClient } from "@supabase/ssr";

export async function isAuthenticated(request: NextRequest): Promise<boolean> {
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
      },
    }
  );

  const { data, error } = await supabase.auth.getUser();
  return data?.user !== null && error === null;
}
import { NextRequest } from "next/server";

