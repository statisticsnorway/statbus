"use client";

import { useEffect, useRef, useState } from "react";
import { Spinner } from "@/components/ui/spinner";
import { useBaseData, refreshBaseDataAtom } from "@/atoms/base-data";
import { useWorkerStatus } from "@/atoms/worker_status";
import { useAtomValue, useSetAtom } from 'jotai';
import { analysisPageVisualStateAtom } from '@/atoms/reports';
import { CheckCircle, XCircle, AlertCircle, Loader2 } from "lucide-react";

export function StatisticalUnitsRefresher({
  children,
}: {
  children: React.ReactNode;
}) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);

  const actualVisualState = useAtomValue(analysisPageVisualStateAtom);
  
  // Determine the state to use for rendering. Default to "checking_status" if not yet mounted.
  const visualStateToRender = mounted ? actualVisualState : {
    state: "checking_status" as const, // Ensure type correctness
    message: "Checking status of data analysis...", // Default message for checking_status
    isImporting: null,
    isDerivingUnits: null,
    isDerivingReports: null,
  };
  const { state, message, isImporting, isDerivingUnits, isDerivingReports } = visualStateToRender;
  
  const workerStatus = useWorkerStatus();
  const { hasStatisticalUnits } = useBaseData(); // For the effect's logic
  const doRefreshBaseData = useSetAtom(refreshBaseDataAtom);
  const refreshAttemptedRef = useRef(false);

  useEffect(() => {
    if (!mounted) { // Don't run the effect's logic until mounted
      return;
    }

    // Condition to trigger refresh:
    // 1. All backend jobs are done (not importing, not deriving units, not deriving reports).
    // 2. No errors in workerStatus.
    // 3. Statistical units are not yet confirmed (hasStatisticalUnits is false).
    // 4. Refresh hasn't been attempted yet in this component instance.
    if (
      !workerStatus.loading &&
      !workerStatus.error &&
      !workerStatus.isImporting &&
      !workerStatus.isDerivingUnits &&
      !workerStatus.isDerivingReports &&
      !hasStatisticalUnits &&
      !refreshAttemptedRef.current
    ) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("StatisticalUnitsRefresher: All jobs complete, no units yet. Triggering refreshBaseData.");
      }
      doRefreshBaseData();
      refreshAttemptedRef.current = true;
    }
  }, [mounted, workerStatus, hasStatisticalUnits, doRefreshBaseData]); // Added mounted to dependencies

  if (state === "checking_status") {
    return (
      <div className="flex flex-col justify-center items-center">
        <Loader2 className="h-8 w-8 animate-spin text-gray-500" />
        <p className="mt-2 text-gray-700">{message || "Checking status..."}</p>
      </div>
    );
  }

  const renderStatusItem = (
    label: string,
    isActive: boolean | null, // Can be null from workerStatus
    isDone: boolean
  ) => {
    return (
      <div className="flex items-center space-x-3 py-2">
        <div className="w-8">
          {isActive === true ? ( // Explicitly check for true
            <Loader2 className="h-6 w-6 animate-spin" />
          ) : isDone ? (
            <CheckCircle className="h-6 w-6 text-green-500" />
          ) : (
            <div className="h-6 w-6 rounded-full border-2 border-gray-300" />
          )}
        </div>
        <div className="flex-1">
          <p className={`font-medium ${isActive === true ? "text-black" : "text-gray-600"}`}>
            {label}
          </p>
        </div>
      </div>
    );
  };

  if (state === "in_progress" || state === "finished") {
    const importDone = !!(state === "finished" || (!isImporting && (isDerivingUnits || isDerivingReports)));
    const unitsDone = !!(state === "finished" || (!isDerivingUnits && isDerivingReports));
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
                {message || "All processes completed successfully"}
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
        <p className="text-red-500 text-sm">{message}</p>
      </div>
    );
  }

  // Fallback (should ideally not be reached if visualState covers all cases)
  return <Spinner message="Processing..." />;
}
