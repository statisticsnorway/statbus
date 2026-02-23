"use client";

import { useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { Spinner } from "@/components/ui/spinner";
import { useBaseData, refreshBaseDataAtom } from "@/atoms/base-data";
import { useWorkerStatus, COMMAND_LABELS, type PhaseStatus } from "@/atoms/worker_status";
import { useAtomValue, useSetAtom } from 'jotai';
import { analysisPageVisualStateAtom } from '@/atoms/reports';
import { CheckCircle, XCircle, AlertCircle, Loader2 } from "lucide-react";
import { Progress } from "@/components/ui/progress";

function PhaseProgressBar({ phase }: { phase: PhaseStatus | null }) {
  if (!phase || !phase.active || phase.progress.length === 0) return null;
  return (
    <div className="mt-2 space-y-2">
      {phase.progress.map((step) => {
        const label = COMMAND_LABELS[step.step] ?? step.step;
        const pct = step.total > 0 ? Math.round((step.completed / step.total) * 100) : 0;
        return (
          <div key={step.step}>
            <div className="flex justify-between text-xs text-gray-500 mb-0.5">
              <span>{label}</span>
              <span>{pct}%</span>
            </div>
            <Progress value={pct} className="h-1.5" />
          </div>
        );
      })}
    </div>
  );
}

export function StatisticalUnitsRefresher({
  children,
}: {
  children: React.ReactNode;
}) {
  const [mounted, setMounted] = useState(false);
  useGuardedEffect(() => {
    setMounted(true);
  }, [], 'StatisticalUnitsRefresher:setMounted');

  const actualVisualState = useAtomValue(analysisPageVisualStateAtom);

  const visualStateToRender = mounted ? actualVisualState : {
    state: "checking_status" as const,
    message: "Checking status of data analysis...",
    isImporting: null,
    isDerivingUnits: null,
    isDerivingReports: null,
  };
  const { state, message, isImporting, isDerivingUnits, isDerivingReports } = visualStateToRender;

  const workerStatus = useWorkerStatus();
  const { hasStatisticalUnits } = useBaseData();
  const doRefreshBaseData = useSetAtom(refreshBaseDataAtom);
  const refreshAttemptedRef = useRef(false);

  useGuardedEffect(() => {
    if (!mounted) {
      return;
    }

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
  }, [mounted, workerStatus, hasStatisticalUnits, doRefreshBaseData], 'StatisticalUnitsRefresher:triggerRefresh');

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
    isActive: boolean | null,
    isDone: boolean,
    phase: PhaseStatus | null,
  ) => {
    return (
      <div className="py-2">
        <div className="flex items-center space-x-3">
          <div className="w-8">
            {isActive === true ? (
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
        {isActive && phase && <div className="ml-11"><PhaseProgressBar phase={phase} /></div>}
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

          {renderStatusItem("Importing Data", isImporting, importDone, null)}
          {renderStatusItem("Deriving Statistical Units", isDerivingUnits, unitsDone, workerStatus.derivingUnits)}
          {renderStatusItem("Generating Reports", isDerivingReports, reportsDone, workerStatus.derivingReports)}

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

  // Fallback
  return <Spinner message="Processing..." />;
}
