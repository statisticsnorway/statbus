"use client";
import { chart } from "highcharts";
import { useEffect, useRef, useState } from "react";
import { OptionsFilter } from "../search/components/options-filter";

export const HistoricalReportChart = () => {
  const ref = useRef<HTMLDivElement>(null);

  const data = [
    {
      id: "2014",
      name: "Establishments in 2014",
      data: [120, 130, 125, 135, 140, 145, 150, 155, 160, 165, 170, 175],
    },
    {
      id: "2015",
      name: "Establishments in 2015",
      data: [180, 185, 180, 175, 170, 165, 160, 155, 150, 145, 140, 135],
    },
    {
      id: "2016",
      name: "Establishments in 2016",
      data: [130, 135, 140, 145, 150, 155, 160, 165, 170, 175, 180, 185],
    },
    {
      id: "2017",
      name: "Establishments in 2017",
      data: [190, 185, 180, 175, 170, 165, 160, 155, 150, 145, 140, 135],
    },
    {
      id: "2018",
      name: "Establishments in 2018",
      data: [130, 135, 130, 125, 120, 115, 110, 105, 100, 95, 90, 85],
    },
    {
      id: "2019",
      name: "Establishments in 2019",
      data: [90, 95, 100, 105, 110, 115, 120, 125, 130, 135, 140, 145],
    },
    {
      id: "2020",
      name: "Establishments in 2020",
      data: [150, 155, 160, 165, 170, 175, 180, 185, 190, 195, 200, 205],
    },
    {
      id: "2021",
      name: "Establishments in 2021",
      data: [210, 205, 200, 195, 190, 185, 180, 175, 170, 165, 160, 155],
    },
    {
      id: "2022",
      name: "Establishments in 2022",
      data: [150, 155, 160, 165, 170, 160, 150, 140, 130, 120, 110, 100],
    },
    {
      id: "2023",
      name: "Establishments in 2023",
      data: [100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210],
    },
    {
      id: "2024",
      name: "Establishments in 2024",
      data: [215, 210, 205, 200, 195, 190, 185, 180, 175, 170, 165, 160],
    },
  ];
  const [year, setYear] = useState<string | null>("2014");
  const [series, setSeries] = useState<{ name: string; data: number[] } | null>(
    null
  );

  useEffect(() => {
    setSeries(data.find(({ id }) => id === year) ?? null);
  }, [year]);

  useEffect(() => {
    if (ref.current) {
      chart({
        chart: {
          renderTo: ref.current,
        },
        series: [
          {
            type: "bar",
            name: series?.name,
            data: series?.data,
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
          { label: "2014", value: "2014" },
          { label: "2015", value: "2015" },
        ]}
        selectedValues={[year]}
        onToggle={(option) => {
          setYear(option.value);
        }}
        onReset={() => {}}
      />
      <div ref={ref} />
    </section>
  );
};
