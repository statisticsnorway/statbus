import {Metadata} from "next";
import StatBusChart from "@/app/reports/statbus-chart";
import {createClient} from "@/lib/supabase/server";
import {DrillDown} from "@/app/reports/types/drill-down";

export const metadata: Metadata = {
    title: "StatBus | Reports"
}

export default async function ReportsPage() {
    const client = createClient();
    const {data: drillDown, error} = await client.rpc('statistical_unit_facet_drilldown').returns<DrillDown>()

    if (error) {
        console.error('⚠️failed to fetch statistical unit facet drill down data', error);
        return (
            <p className="p-24 text-center">
                Sorry! We failed to fetch statistical unit facet drill down data.
            </p>
        )
    }

    return (
        <>
            <main className="flex flex-col py-8 px-2 md:py-24 max-w-5xl mx-auto w-full">
                <h1 className="font-medium text-xl text-center mb-12">StatBus Reports</h1>
                <StatBusChart drillDown={drillDown}/>
            </main>
        </>
    )
}
