'use client';

import {useCallback, useEffect} from "react";
import {DrillDown, DrillDownPoint} from "@/app/reports/types/drill-down";
import * as highcharts from "highcharts";
import HC_drilldown from "highcharts/modules/drilldown";
import HC_a11y from "highcharts/modules/accessibility";
import {BreadCrumb} from "@/app/reports/bread-crumb";
import {DrillDownChart} from "@/app/reports/drill-down-chart";
import {useDrillDownData} from "@/app/reports/use-drill-down-data";
import {InfoBox} from "@/components/info-box";


export default function StatBusChart(props: { readonly drillDown: DrillDown }) {
    const {drillDown, region, setRegion, activityCategory, setActivityCategory} = useDrillDownData(props.drillDown);

    useEffect(() => {
        HC_a11y(highcharts);
        HC_drilldown(highcharts);
    }, []);

    const selectRegion = useCallback((point: DrillDownPoint) => {
        setRegion(point);
    }, [setRegion]);

    const selectActivityCategory = useCallback((point: DrillDownPoint) => {
        setActivityCategory(point);
    }, [setActivityCategory]);

    return (
        <div className="w-full space-y-6 p-6">
            <InfoBox>
               
               
            </InfoBox>
            <div className="p-6 space-y-6 border-l-4 border-gray-200 bg-gray-50">
                <BreadCrumb
                    topLevelText="All Regions"
                    points={drillDown.breadcrumb.region}
                    selected={region}
                    onSelect={setRegion}
                />
                <DrillDownChart
                    points={drillDown.available.region}
                    onSelect={selectRegion}
                />
            </div>
            <div className="p-6 space-y-6 border-l-4 border-gray-200 bg-gray-50">
                <BreadCrumb
                    topLevelText="All Activity Categories"
                    points={drillDown.breadcrumb.activity_category}
                    selected={activityCategory}
                    onSelect={setActivityCategory}
                />
                <DrillDownChart
                    points={drillDown.available.activity_category}
                    onSelect={selectActivityCategory}
                />
            </div>
        </div>
    )
}

