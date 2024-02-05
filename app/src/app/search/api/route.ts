import {NextResponse} from "next/server";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function GET(request: Request) {
    const {searchParams} = new URL(request.url)

    if (!searchParams.has('limit')) {
        searchParams.set('limit', '10')
    }

    if (!searchParams.has('order')) {
        searchParams.set('order', 'enterprise_id.desc')
    }

    if (!searchParams.has('select')) {
        searchParams.set('select', 'name, tax_reg_ident, primary_activity_category_path, legal_unit_id, physical_region_path')
    }

    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/statistical_unit?${searchParams}`, {
        method: 'GET',
        headers: {
            'Prefer': 'count=exact',
            'Range-Unit': 'items'
        },
    })

    if (!response.ok) {
        return NextResponse.json({error: response.statusText})
    }

    const statisticalUnits = await response.json()
    const count = response.headers.get('content-range')?.split('/')[1]
    return NextResponse.json({statisticalUnits, count: parseInt(count ?? '-1', 10)})
}
