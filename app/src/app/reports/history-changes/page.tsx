"use client";

import { HistoryReports } from "../history-reports";
import { HistoryChangesChart } from "./history-changes-chart";

export default function HistoryChangesPage() {
  return (
    <HistoryReports
      title="Changes over time"
      subtitle="Annual overview of births, deaths, name changes, and other changes"
      seriesCodes={[
        "births",
        "deaths",
        "name_change_count",
        "primary_activity_category_change_count",
        "physical_region_change_count",
      ]}
    >
      {({ history, isYearlyView, onYearSelect }) => (
        <HistoryChangesChart
          history={history}
          isYearlyView={isYearlyView}
          onYearSelect={onYearSelect}
        />
      )}
    </HistoryReports>
  );
}
