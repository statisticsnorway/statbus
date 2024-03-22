"use client";
import { chart } from "highcharts";
import { useEffect, useRef, useState } from "react";
import { OptionsFilter } from "../search/components/options-filter";
import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<any[], string> = (...args) =>
  fetch(...args).then((res) => res.json());

export const HistoricalReportChart = () => {
  const ref = useRef<HTMLDivElement>(null);

  const [year, setYear] = useState<string | null>("2024");

  const { data } = useSWR<any[]>(
    `/api/historical-reports?year=${year}`,
    fetcher
  );

  useEffect(() => {
    if (ref.current) {
      chart({
        chart: {
          renderTo: ref.current,
        },
        series: [
          {
            type: "bar",
            data: data,
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
        }}
        onReset={() => {}}
      />
      <div ref={ref} />
    </section>
  );
};
