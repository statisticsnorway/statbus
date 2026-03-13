"use client";

import { HistoryReports } from "./history-reports";
import { UnitCountChart } from "./unit-count-chart";

export default function UnitCountsPage() {
  return (
    <HistoryReports
      title="Units over time"
      subtitle="Total number of enterprises, legal units, and establishments over time"
      seriesCodes={["countable_count"]}
    >
      {({ history, isYearlyView, onYearSelect }) => (
        <UnitCountChart
          history={history}
          isYearlyView={isYearlyView}
          onYearSelect={onYearSelect}
        />
      )}
    </HistoryReports>
  );
}
