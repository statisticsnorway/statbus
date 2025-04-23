"use client";

import { useEffect, useState, useCallback } from "react";
import { Spinner } from "@/components/ui/spinner";
import { useBaseData } from "@/app/BaseDataClient";
// No longer need useSystemStatusNotifications or baseDataStore directly here

type AnalysisState = "checking_status" | "deriving" | "finished" | "failed";

export function StatisticalUnitsRefresher({
  children,
}: {
  children: React.ReactNode;
}) {
  const [state, setState] = useState<AnalysisState>("checking_status");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  // Get status and refresh function directly from context
  const { workerStatus, hasStatisticalUnits, refreshHasStatisticalUnits } = useBaseData();

  // Effect to determine component state based on context status
  useEffect(() => {
    const { isImporting, isDerivingUnits, isDerivingReports, isLoading, error } = workerStatus;

    if (isLoading) {
      setState("checking_status");
      return;
    }

    if (error) {
      setState("failed");
      setErrorMessage(`Error checking derivation status: ${error}`);
      return;
    }

    if (isImporting === true || isDerivingUnits === true || isDerivingReports === true) {
      setState("deriving");
    } else {
      // Import and Derivation are finished according to context, now check if units exist
      // We might need to refresh hasStatisticalUnits explicitly if it could be stale
      // relative to the derivation finishing. Let's add a check.
      const checkUnits = async () => {
        const currentHasUnits = await refreshHasStatisticalUnits(); // Refresh and get latest
        if (currentHasUnits) {
          setState("finished");
        } else {
          // Derivation finished, but no units found
          setState("failed");
          setErrorMessage("Data analysis completed, but no statistical units were found.");
        }
      };
      checkUnits();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
       // Depend on specific properties instead of the whole object
       workerStatus.isImporting,
       workerStatus.isDerivingUnits,
       workerStatus.isDerivingReports,
       workerStatus.isLoading,
       workerStatus.error,
       refreshHasStatisticalUnits // Keep this dependency
     ]);

  if (state === "checking_status") {
    return <Spinner message="Checking status of data analysis..." />;
  }

  if (state === "deriving") {
    return <Spinner message="Analysing data for Search and Reports..." />;
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
