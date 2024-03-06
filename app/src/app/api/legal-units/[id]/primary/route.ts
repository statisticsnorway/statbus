import {NextResponse} from "next/server";
import {createClient} from "@/lib/supabase/server";

export async function POST(request: Request, {params: {id}}: { readonly params: { id: string } }) {
  try {
    const enterprise: { id: number } = await request.json()
    const legalUnitId = parseInt(id, 10);

    if (!enterprise?.id || !legalUnitId) {
      return NextResponse.json({error: 'either enterprise id or legal unit id is missing'}, {status: 400})
    }

    const client = createClient()
    const {data, error} = await client.rpc('connect_legal_unit_to_enterprise', {
      legal_unit_id: legalUnitId,
      enterprise_id: enterprise.id
    })

    if (error) {
      return NextResponse.json({error: 'failed to connect legal unit to enterprise'}, {status: 500})
    }

    return NextResponse.json(data)

  } catch (e) {
    console.error('failed to connect legal unit to enterprise', e)
    return NextResponse.json({error: 'failed to connect legal unit to enterprise'}, {status: 500})
  }
}
