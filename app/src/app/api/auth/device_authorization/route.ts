import { NextRequest, NextResponse } from 'next/server'

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData()
    const clientId = formData.get('client_id') as string
    const scope = formData.get('scope') as string

    // This URL must point to your PostgREST instance.
    // It is assumed to be configured via an environment variable.
    const restUrl = process.env.POSTGREST_URL
    if (!restUrl) {
      console.error('POSTGREST_URL environment variable is not set.')
      return new NextResponse('Internal server configuration error.', { status: 500 })
    }
    
    // Call the RPC function `request_device_authorization`
    const rpcResponse = await fetch(`${restUrl}/rpc/request_device_authorization`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // PostgREST needs 'Prefer: params=single-object' for single JSON object params
        'Prefer': 'params=single-object',
      },
      body: JSON.stringify({
        p_client_id: clientId,
        p_scope: scope,
      }),
    })

    if (!rpcResponse.ok) {
      const errorBody = await rpcResponse.text()
      console.error('Error from PostgREST device auth RPC:', { status: rpcResponse.status, body: errorBody })
      return new NextResponse(`Error from database: ${rpcResponse.statusText}`, { status: rpcResponse.status })
    }

    const data = await rpcResponse.json()

    return NextResponse.json(data)
  } catch (error) {
    console.error('Error in device authorization endpoint:', error)
    const message = error instanceof Error ? error.message : 'An unknown error occurred'
    return new NextResponse(message, { status: 500 })
  }
}
