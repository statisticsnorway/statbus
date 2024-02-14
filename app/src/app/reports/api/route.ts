import {NextResponse} from "next/server";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function GET(request: Request) {
    const {searchParams: requestParams} = new URL(request.url)

    const params = new URLSearchParams()

    if (requestParams.has('unit_type')) {
        params.set('unit_type', requestParams.get('unit_type') as string)
    }

    if (requestParams.has('region_path')) {
        params.set('region_path', requestParams.get('region_path') as string)
    }

    if (requestParams.has('activity_category_path')) {
        params.set('activity_category_path', requestParams.get('activity_category_path') as string)
    }

    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/statistical_unit_facet_drilldown?${params}`, {
        method: 'GET'
    });

    if (!response.ok) {
        return NextResponse.json({error: response.statusText})
    }

    const data = await response.json()
    return NextResponse.json(data)
}
