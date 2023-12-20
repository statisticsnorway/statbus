import {NextResponse} from 'next/server'
import {createClient} from "@/app/auth/lib/supabase.server.client";

export async function POST(request: Request) {
  const requestUrl = new URL(request.url)
  const formData = await request.formData()
  const email = String(formData.get('email'))
  const password = String(formData.get('password'))
  const supabaseClient = createClient()

  const { error } = await supabaseClient.auth.signInWithPassword({
    email,
    password,
  })

  if (error) {
    console.error('user login failed')
  }

  return NextResponse.redirect(requestUrl.origin, {
    status: 302,
  })
}
