"use client";
import { chart } from "highcharts";
import { useEffect, useRef } from "react";
import { OptionsFilter } from "../search/components/options-filter";
import { Button } from "@/components/ui/button";
import { ArrowRight } from "lucide-react";
import useHistoricalData from "./use-historical-data";

export const HistoricalReportChart = () => {
  const ref = useRef<HTMLDivElement>(null);

  const { data, year, setYear, unitType, setUnitType, type, setType } =
    useHistoricalData();

  useEffect(() => {
    if (ref.current) {
      chart({
        chart: {
          renderTo: ref.current,
        },
        xAxis: {
          type: "category",
        },
        tooltip: {
          headerFormat: "",
          pointFormat: "{point.name}: <b>{point.y}</b>",
          outside: true,
          useHTML: true,
        },
        plotOptions: {
          series: {
            borderWidth: 0,
            dataLabels: {
              enabled: true,
              format: "{point.y}",
            },
          },
        },
        credits: {
          href: "",
        },
        series: [
          {
            type: "bar",
            showInLegend: false,
            data: data,
            point: {
              events: {
                click: (e) => {
                  // console.log(e);
                  setType("year-month");
                  // @ts-ignore
                  setYear(`${e.point.options.year}`);
                },
              },
            },
          },
        ],
      });
    }
  });

  return (
    <section className="w-full">
      <OptionsFilter
        title="Year"
        options={[
          { label: "2023", value: "2023" },
          { label: "2024", value: "2024" },
        ]}
        selectedValues={[year]}
        onToggle={(option) => {
          setYear(option.value);
          setType("year-month");
        }}
        onReset={() => {}}
      />
      <OptionsFilter
        title="Unit type"
        options={[
          {
            label: "Enterprise",
            value: "enterprise",
            humanReadableValue: "Enterprise",
            className: "bg-enterprise-100",
          },
          {
            label: "Legal Unit",
            value: "legal_unit",
            humanReadableValue: "Legal Unit",
            className: "bg-legal_unit-100",
          },
          {
            label: "Establishment",
            value: "establishment",
            humanReadableValue: "Establishment",
            className: "bg-establishment-100",
          },
        ]}
        selectedValues={[unitType]}
        onToggle={(option) => {
          setUnitType(option.value);
        }}
        onReset={() => {}}
      />
      <div className="flex flex-wrap">
        <Button
          size="sm"
          variant="ghost"
          onClick={() => {
            setType("year");
            setYear(null);
          }}
        >
          All years
        </Button>
        {year && (
          <div className="flex items-center space-x-2">
            <ArrowRight size={18} />
            <Button size="sm" variant="ghost">
              {year}
            </Button>
          </div>
        )}
      </div>
      <div ref={ref} />
    </section>
  );
};
