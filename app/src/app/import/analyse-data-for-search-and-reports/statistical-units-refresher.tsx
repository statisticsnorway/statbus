"use client";

import { useEffect, useState } from "react";
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";
import { Spinner } from "@/components/ui/spinner";
import { useBaseData } from "@/app/BaseDataClient";

type AnalysisState = "checking" | "refreshing" | "finished" | "failed";

export function StatisticalUnitsRefresher({
  children,
}: {
  children: React.ReactNode;
}) {
  const [state, setState] = useState("checking" as AnalysisState);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const { hasStatisticalUnits, refreshHasStatisticalUnits } = useBaseData();

  useEffect(() => {
    const checkAndRefresh = async () => {
      if (state == "checking") {
        if (hasStatisticalUnits) {
          setState("finished");
        } else {
          setState("refreshing");
        }
      }

      if (state == "refreshing") {
        try {
          const client = await createSupabaseBrowserClientAsync();
          const { status, statusText, data, error } = await client.rpc(
            "statistical_unit_refresh_now"
          );

          if (error) {
            setState("failed");
            setErrorMessage(error.message);
          } else {
            setState("finished");
            refreshHasStatisticalUnits();
          }
        } catch (error) {
          setState("failed");
          setErrorMessage("Error refreshing statistical units");
        }
      }
    };

    checkAndRefresh();
  }, [state, hasStatisticalUnits, refreshHasStatisticalUnits]);

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
        <p className="text-red-500">{errorMessage}</p>
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
