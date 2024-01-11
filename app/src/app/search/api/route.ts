import {createClient} from "@/lib/supabase/server";
import {NextResponse} from "next/server";

export async function GET(request: Request) {
    const {searchParams} = new URL(request.url)
    const client = createClient()
    const searchTerm = searchParams.get('q')

    const {data: legalUnits, count, error} = await client
        .from('legal_unit')
        .select('*', {count: 'exact'})
        .ilike('name', `*${searchTerm}*`)
        .limit(10)

    if (error) {
        return NextResponse.json({error})
    }

    return NextResponse.json({legalUnits, count})
}
