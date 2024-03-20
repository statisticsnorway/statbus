import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState } from "react";
import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<DrillDown, string> = (...args) =>
  fetch(...args).then((res) => res.json());

export const useDrillDownData = (initialDrillDown: DrillDown) => {
  const [region, setRegion] = useState<DrillDownPoint | null>(null);
  const [activityCategory, setActivityCategory] =
    useState<DrillDownPoint | null>(null);

  const params = new URLSearchParams();
  if (region?.path) {
    params.set("region_path", region?.path);
  }
  if (activityCategory?.path) {
    params.set("activity_category_path", activityCategory?.path);
  }
  console.log(params.toString());
  const { data: drillDown } = useSWR<DrillDown>(
    `/api/reports?${params}`,
    fetcher,
    {
      fallbackData: initialDrillDown,
      keepPreviousData: true,
    }
  );

  return {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};
