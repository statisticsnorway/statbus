"use client";

import { useEffect, useState } from "react";
import { Spinner } from "@/components/ui/spinner";
import { useBaseData } from "@/app/BaseDataClient";
import { CheckCircle, XCircle, AlertCircle } from "lucide-react";

type AnalysisState = "checking_status" | "in_progress" | "finished" | "failed";

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
      setState("in_progress");
    } else {
      // Import and Derivation are finished according to context, now check if units exist
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
       workerStatus.isImporting,
       workerStatus.isDerivingUnits,
       workerStatus.isDerivingReports,
       workerStatus.isLoading,
       workerStatus.error,
       refreshHasStatisticalUnits
     ]);

  if (state === "checking_status") {
    return <Spinner message="Checking status of data analysis..." />;
  }

  const { isImporting, isDerivingUnits, isDerivingReports } = workerStatus;

  const renderStatusItem = (
    label: string, 
    isActive: boolean | null, 
    isDone: boolean
  ) => {
    return (
      <div className="flex items-center space-x-3 py-2">
        <div className="w-8">
          {isActive ? (
            <Spinner className="h-6 w-6" />
          ) : isDone ? (
            <CheckCircle className="h-6 w-6 text-green-500" />
          ) : (
            <div className="h-6 w-6 rounded-full border-2 border-gray-300" />
          )}
        </div>
        <div className="flex-1">
          <p className={`font-medium ${isActive ? "text-black" : "text-gray-600"}`}>
            {label}
          </p>
        </div>
      </div>
    );
  };

  if (state === "in_progress" || state === "finished") {
    // Determine which steps are done based on current state
    const importDone = state === "finished" || (!isImporting && (isDerivingUnits || isDerivingReports));
    const unitsDone = state === "finished" || (!isDerivingUnits && isDerivingReports);
    const reportsDone = state === "finished";

    return (
      <div className="space-y-6">
        <div className="bg-white rounded-lg border p-4 shadow-sm">
          <h3 className="text-lg font-medium mb-4">Analysis Progress</h3>
          
          {renderStatusItem("Importing Data", isImporting, importDone)}
          {renderStatusItem("Deriving Statistical Units", isDerivingUnits, unitsDone)}
          {renderStatusItem("Generating Reports", isDerivingReports, reportsDone)}
          
          {state === "finished" && (
            <div className="mt-4 pt-4 border-t border-gray-200 text-center">
              <p className="text-green-600 font-medium">
                All processes completed successfully
              </p>
            </div>
          )}
        </div>
        
        {state === "finished" && children}
      </div>
    );
  }

  if (state === "failed") {
    return (
      <div className="bg-white rounded-lg border border-red-200 p-4 shadow-sm">
        <div className="flex items-center space-x-3 text-red-600 mb-3">
          <AlertCircle className="h-6 w-6" />
          <h3 className="text-lg font-medium">Analysis Failed</h3>
        </div>
        <p className="text-gray-700 mb-2">
          Data analysis for Search and Reports failed to complete.
        </p>
        <p className="text-red-500 text-sm">{errorMessage}</p>
      </div>
    );
  }

  // Fallback (should not reach here)
  return <Spinner message="Processing..." />;
}
