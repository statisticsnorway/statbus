'use client';

import {useEffect} from "react";
import {DrillDown} from "@/app/reports/types/drill-down";
import * as highcharts from "highcharts";
import HC_drilldown from "highcharts/modules/drilldown";
import HC_a11y from "highcharts/modules/accessibility";
import {BreadCrumb} from "@/app/reports/bread-crumb";
import {DrillDownChart} from "@/app/reports/drill-down-chart";
import {useDrillDownData} from "@/app/reports/use-drill-down-data";
import {SearchLink} from "@/app/reports/search-link";

export default function StatBusChart(props: { readonly drillDown: DrillDown }) {
    const {drillDown, region, setRegion, activityCategory, setActivityCategory} = useDrillDownData(props.drillDown);

    useEffect(() => {
        HC_a11y(highcharts);
        HC_drilldown(highcharts);
    }, []);

    return (
        <div className="w-full space-y-8">
            <div className="space-y-6 bg-gray-50 p-4">
                <BreadCrumb
                    topLevelText="All Regions"
                    points={drillDown.breadcrumb.region}
                    selected={region}
                    onSelect={setRegion}
                />
                <DrillDownChart
                    points={drillDown.available.region}
                    onSelect={setRegion}
                />
            </div>
            <div className="bg-gray-50 p-6">
                <BreadCrumb
                    topLevelText="All Activity Categories"
                    points={drillDown.breadcrumb.activity_category}
                    selected={activityCategory}
                    onSelect={setActivityCategory}
                />
                <DrillDownChart
                    points={drillDown.available.activity_category}
                    onSelect={setActivityCategory}
                />
            </div>

          <div className="flex justify-end p-6 space-y-6 bg-gray-100">
            <SearchLink region={region} activityCategory={activityCategory}/>
          </div>
        </div>
    )
}

