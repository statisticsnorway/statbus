import { NextRequest, NextResponse } from 'next/server'

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData()
    const grantType = formData.get('grant_type') as string
    const deviceCode = formData.get('device_code') as string

    if (grantType !== 'urn:ietf:params:oauth:grant-type:device_code') {
      return new NextResponse('Unsupported grant_type', { status: 400 })
    }

    if (!deviceCode) {
      return new NextResponse('Missing device_code', { status: 400 })
    }
    
    const restUrl = process.env.POSTGREST_URL
    if (!restUrl) {
      console.error('POSTGREST_URL environment variable is not set.')
      return new NextResponse('Internal server configuration error.', { status: 500 })
    }
    
    // Call the RPC function `poll_device_authorization`
    const rpcResponse = await fetch(`${restUrl}/rpc/poll_device_authorization`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Prefer': 'params=single-object',
      },
      body: JSON.stringify({
        p_device_code: deviceCode,
      }),
    })

    const data = await rpcResponse.json()

    // PostgREST doesn't return the status code set by `set_config` in the body,
    // but it does set it in the response headers. We'll use the presence of
    // an 'error' key in the JSON body to determine the response code.
    if (data.error) {
      return NextResponse.json(data, { status: 400 })
    }

    // If no error, it's a success response with the token.
    return NextResponse.json(data)
  } catch (error) {
    console.error('Error in token endpoint:', error)
    const message = error instanceof Error ? error.message : 'An unknown error occurred'
    return new NextResponse(message, { status: 500 })
  }
}
