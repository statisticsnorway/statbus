import {NextResponse} from 'next/server'
import {createClient} from "@/app/auth/lib/supabase.server.client";

export async function POST(request: Request) {
  const requestUrl = new URL(request.url)
  const supabaseClient = createClient()
  const { error } = await supabaseClient.auth.signOut()

  if (error) {
    console.error('user logout failed')
  }

  return NextResponse.redirect(requestUrl.origin, {
    status: 302,
  })
}
