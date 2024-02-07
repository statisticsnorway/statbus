import {NextResponse} from "next/server";
import {Tables} from "@/lib/database.types";
import {getStatisticalUnits} from "@/app/search/search-requests";
import {toCSV} from "@/lib/csv-utils";

export async function GET(request: Request) {
    const {searchParams} = new URL(request.url)

    if (!searchParams.has('order')) {
        searchParams.set('order', 'enterprise_id.desc')
    }

    if (!searchParams.has('select')) {
        searchParams.set('select', '*')
    }

    const statisticalUnitsResponse = await getStatisticalUnits(searchParams);

    if (!statisticalUnitsResponse.ok) {
        return NextResponse.error()
    }

    const statisticalUnits: Tables<Partial<'statistical_unit'>>[] = await statisticalUnitsResponse.json()

    const {header, body} = toCSV(statisticalUnits)

    return new Response(header + body, {
        headers: {
            'Content-Type': 'text/csv',
            'Content-Disposition': 'attachment; filename="statistical_units.csv"'
        }
    })
}

