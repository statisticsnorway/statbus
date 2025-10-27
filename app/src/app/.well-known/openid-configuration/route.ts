import { NextResponse } from 'next/server'

export async function GET() {
  const issuer = process.env.STATBUS_URL
  if (!issuer) {
    return new NextResponse('STATBUS_URL environment variable is not set.', { status: 500 })
  }

  const configuration = {
    issuer: issuer,
    authorization_endpoint: `${issuer}/auth`,
    token_endpoint: `${issuer}/api/auth/token`,
    jwks_uri: `${issuer}/api/auth/jwks`,
    device_authorization_endpoint: `${issuer}/api/auth/device_authorization`,
  }

  return NextResponse.json(configuration)
}
