import {DrillDownPoint} from "@/app/reports/types/drill-down";
import {useEffect, useRef} from "react";
import type {Chart} from "highcharts";
import {chart} from "highcharts";

export const DrillDownChart = ({points, onSelect}: { points: DrillDownPoint[], onSelect: (p: DrillDownPoint) => void }) => {
    const _ref = useRef<HTMLDivElement>(null)
    const _chart = useRef<Chart | null>(null)

    useEffect(() => {
        _chart.current?.destroy();

        if (_ref.current) {
            _chart.current = chart({
                chart: {
                    renderTo: _ref.current,
                    events: {
                        drilldown: (e) => onSelect(e.point.options.custom as DrillDownPoint)
                    },
                    backgroundColor: 'rgb(249, 250, 251)'
                },
                plotOptions: {
                    series: {
                        borderWidth: 0,
                        dataLabels: {
                            enabled: true,
                            format: '{point.y}'
                        }
                    }
                },
                title: {
                    text: ''
                },
                xAxis: {
                    type: 'category'
                },
                yAxis: {
                    title: {
                        text: ''
                    }
                },
                series: [
                    {
                        type: 'bar',
                        showInLegend: false,
                        data: points?.map(toPointOptionObject)
                    }
                ]
            });
        }
    }, [points, onSelect]);

    return (
        <div ref={_ref}/>
    )
}

const toPointOptionObject = (point: DrillDownPoint) => ({
    name: point.name,
    y: point.count,
    drilldown: point.has_children ? '1' : '',
    custom: point
})
