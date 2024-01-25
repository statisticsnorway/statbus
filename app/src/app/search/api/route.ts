import {NextResponse} from "next/server";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function GET(request: Request) {
    const {searchParams} = new URL(request.url)

    if (!searchParams.has('limit')) {
        searchParams.set('limit', '10')
    }

    if (!searchParams.has('order')) {
        searchParams.set('order', 'tax_reg_ident.desc')
    }

    if (!searchParams.has('select')) {
        searchParams.set('select', 'tax_reg_ident,name, name, primary_activity_category_code')
    }

    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/legal_unit_region_activity_category_stats_current?${searchParams}`, {
        method: 'GET',
        headers: {
            'Prefer': 'count=exact',
            'Range-Unit': 'items'
        },
    })

    if (!response.ok) {
        return NextResponse.json({error: response.statusText})
    }

    const legalUnits = await response.json()
    const count = response.headers.get('content-range')?.split('/')[1]
    return NextResponse.json({legalUnits, count: parseInt(count ?? '-1', 10)})
}
