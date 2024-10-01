import { cookies } from "next/headers";
import { CookieOptions, createServerClient } from "@supabase/ssr";
import { Database } from "@/lib/database.types";

export const createClient = () => {
  const cookie = cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookie.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          try {
            cookie.set({ name, value, ...options });
          } catch (e) {
            // The `set` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing user sessions.
            // Ref: https://github.com/vercel/next.js/blob/canary/examples/with-supabase/utils/supabase/server.ts
          }
        },
        remove(name: string, options: CookieOptions) {
          try {
            cookie.set({ name, value: "", ...options });
          } catch (e) {
            // The `set` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing user sessions.
            // Ref: https://github.com/vercel/next.js/blob/canary/examples/with-supabase/utils/supabase/server.ts
          }
        },
      },
    }
  );
};
