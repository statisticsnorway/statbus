"use client";

import { useBaseData } from "@/atoms/base-data";
import { HistoryReports } from "../history-reports";
import { StatisticalVariablesChart } from "./statistical-variables-chart";


export default function StatisticalVariablesPage() {
const {statDefinitions} = useBaseData()
const statsSummaryCodes = statDefinitions
  .filter((s) => s.type === "int" || s.type === "float")
  .map((s) => `stats_summary.${s.code}.sum`);

  return (
    <HistoryReports
      title="Statistical variables over time"
      subtitle="Statistical variable totals for enterprises, legal units, and establishments over time"
      seriesCodes={statsSummaryCodes}
    >
      {({ history, isYearlyView, onYearSelect }) => (
        <StatisticalVariablesChart
          history={history}
          isYearlyView={isYearlyView}
          onYearSelect={onYearSelect}
        />
      )}
    </HistoryReports>
  );
}
