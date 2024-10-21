"use client";

import { useEffect, useState } from "react";
import { refreshStatisticalUnits } from "@/components/command-palette/command-palette-server-actions";
import { Spinner } from "@/components/ui/spinner";
import { useGettingStarted, } from "../GettingStartedContext";
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";

type AnalysisState = "checking" | "refreshing" | "finished" | "failed";

export function StatisticalUnitsRefresher({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState("checking" as AnalysisState);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const { numberOfStatisticalUnits, refreshNumberOfStatisticalUnits } = useGettingStarted();

  useEffect(() => {
    const checkAndRefresh = async () => {
      if (state == "checking") {
        if (numberOfStatisticalUnits != null) {
          if (numberOfStatisticalUnits > 0) {
            setState("finished");
          } else {
            setState("refreshing");
          }
        }
      }
      if (state == "refreshing") {
        const response = await refreshStatisticalUnits();
        if (response?.error) {
          setState("failed");
          setErrorMessage(response.error);
        } else {
          setState("finished");
          refreshNumberOfStatisticalUnits();
        }
      }
    };

    checkAndRefresh();
  }, [numberOfStatisticalUnits, refreshNumberOfStatisticalUnits, state]);

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
