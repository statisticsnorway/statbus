"use client";

import { useEffect, useState } from "react";
import { refreshStatisticalUnits } from "@/components/command-palette/command-palette-server-actions";
import { Spinner } from "@/components/ui/spinner";
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";

type AnalysisState = "checking" | "refreshing" | "finished" | "failed";

export function StatisticalUnitsRefresher({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState("checking" as AnalysisState);
  const [statisticalUnitsCount, setStatisticalUnitsCount] = useState<number | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const checkAndRefresh = async () => {
      const client = await createSupabaseBrowserClientAsync();

      if (state == "checking") {
        const todayISO = new Date().toISOString().split('T')[0];

        const { count: numberOfStatisticalUnits } = await client
          .from("statistical_unit")
          .select("", { count: "exact" })
          .filter("unit_type", 'eq', "enterprise")
          .filter("valid_from", 'lte', todayISO)
          .filter("valid_to", 'gte', todayISO)
          .limit(1);
        setStatisticalUnitsCount(numberOfStatisticalUnits);
        if (numberOfStatisticalUnits && numberOfStatisticalUnits > 0) {
          setState("finished");
        } else {
          setState("refreshing");
        }
      }
      if (state == "refreshing") {
        const response = await refreshStatisticalUnits();
        if (response?.error) {
          const { count: refreshedCount } = await client
            .from("statistical_unit")
            .select("", { count: "exact" })
            .limit(1);
          setStatisticalUnitsCount(refreshedCount || 0);
        }
        if (response?.error) {
          setState("failed");
          setErrorMessage(response.error);
        } else {
          setState("finished");
        }
      }
    };

    checkAndRefresh();
  }, [state, statisticalUnitsCount]);

  if (state == "checking") {
    return <Spinner message="Checking data for Search and Reports...." />;
  }

  if (state == "refreshing") {
    return <Spinner message="Analysing data for Search and Reports...." />;
  }

  if (state == "failed") {
    return (
      <div className="text-center">
        <p className="text-gray-700">
          Data analysis for Search and Reports Failed
        </p>
        <p className="text-red-500">
          {errorMessage}
        </p>
      </div>
    );
  }

  // state == "finished"
  //Data analysis for Search and Reports completed.
  return (
    <>
      <div className="text-center">
        <p className="text-gray-700">
          Data analysis for Search and Reports completed.
        </p>
      </div>
      {children}
    </>
  );
}
