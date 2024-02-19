import {NextResponse} from "next/server";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function GET(request: Request, {params: {id}}: { params: { id: string } }) {
  const {searchParams: requestParams} = new URL(request.url)
  const searchParams = new URLSearchParams()
  searchParams.set('unit_id', id)
  searchParams.set('unit_type', requestParams.get('unit_type') ?? 'enterprise')

  const authFetch = setupAuthorizedFetchFn()
  const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/statistical_unit_hierarchy?${searchParams}`, {
    method: 'GET'
  });

  if (!response.ok) {
    return NextResponse.json({error: response.statusText})
  }

  const data = await response.json()
  return NextResponse.json(data)
}
