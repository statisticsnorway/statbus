import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useEffect, useState } from "react";
import logger from "@/lib/logger";

export const useDrillDownData = (initialDrillDown: DrillDown) => {
  const [drillDown, setDrillDown] = useState<DrillDown>(initialDrillDown);
  const [region, setRegion] = useState<DrillDownPoint | null>(null);
  const [activityCategory, setActivityCategory] =
    useState<DrillDownPoint | null>(null);

  useEffect(() => {
    (async () => {
      const params = new URLSearchParams();

      if (region?.path) {
        params.set("region_path", region?.path);
      }

      if (activityCategory?.path) {
        params.set("activity_category_path", activityCategory?.path);
      }

      try {
        const res = await fetch(`/api/reports?${params}`);
        setDrillDown(await res.json());
      } catch (e) {
        logger.error(
          { error: e },
          "⚠️failed to fetch statistical unit facet drill down data"
        );
      }
    })();
  }, [region, activityCategory]);

  return {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};
