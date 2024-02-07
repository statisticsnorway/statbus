import {NextResponse} from "next/server";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

async function getStatisticalUnits(searchParams: URLSearchParams) {
    const authFetch = setupAuthorizedFetchFn()
    return await authFetch(`${process.env.SUPABASE_URL}/rest/v1/statistical_unit?${searchParams}`, {
        method: 'GET',
        headers: {
            'Prefer': 'count=exact',
            'Range-Unit': 'items'
        },
    });
}

export async function GET(request: Request) {
    const {searchParams} = new URL(request.url)

    if (!searchParams.has('order')) {
        searchParams.set('order', 'enterprise_id.desc')
    }

    if (!searchParams.has('select')) {
        searchParams.set('select', 'name, tax_reg_ident, primary_activity_category_path, legal_unit_id, physical_region_path')
    }

    if (!searchParams.has('limit')) {
        searchParams.set('limit', '10')
    }

    const statisticalUnitsResponse = await getStatisticalUnits(searchParams);

    if (!statisticalUnitsResponse.ok) {
        return NextResponse.json({error: statisticalUnitsResponse.statusText})
    }

    const statisticalUnits = await statisticalUnitsResponse.json()
    const count = statisticalUnitsResponse.headers.get('content-range')?.split('/')[1]
    return NextResponse.json({statisticalUnits, count: parseInt(count ?? '-1', 10)})
}
