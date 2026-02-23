"use client";

import { cn } from "@/lib/utils";
import { BarChartHorizontal, Search, Upload } from "lucide-react";
import { useWorkerStatus, type PhaseStatus } from "@/atoms/worker_status";
import { Progress } from "@/components/ui/progress";

function computeProgress(phase: PhaseStatus | null): number | null {
  if (!phase || !phase.active || phase.progress.length === 0) return null;
  const totalSum = phase.progress.reduce((acc, s) => acc + s.total, 0);
  const completedSum = phase.progress.reduce((acc, s) => acc + s.completed, 0);
  if (totalSum === 0) return null;
  return Math.round((completedSum / totalSum) * 100);
}

export function NavbarStatusVisualizer() {
  const workerStatus = useWorkerStatus();
  const { isImporting, isDerivingUnits, isDerivingReports, derivingUnits, derivingReports } = workerStatus;

  const unitsPct = computeProgress(derivingUnits);
  const reportsPct = computeProgress(derivingReports);

  return (
    <div className="flex flex-col space-y-4">
      {/* Normal state */}
      <div className="bg-white p-3 rounded-md">
        <h3 className="text-sm font-medium mb-2">Normal Navigation</h3>
        <div className="bg-ssb-dark text-white p-2 rounded-md flex justify-center space-x-3">
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1 border-white",
          )}>
            <Upload size={16} />
            <span>Import</span>
          </div>
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1 border-transparent",
          )}>
            <Search size={16} />
            <span>Statistical Units</span>
          </div>
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1 border-transparent",
          )}>
            <BarChartHorizontal size={16} />
            <span>Reports</span>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-1">Current page has white border</p>
      </div>

      {/* Current system state */}
      <div className="bg-white p-3 rounded-md">
        <h3 className="text-sm font-medium mb-2">Current System State</h3>
        <div className="bg-ssb-dark text-white p-2 rounded-md flex justify-center space-x-3">
          <div
            className={cn(
              "px-3 py-1 rounded flex items-center space-x-2 border-1 relative overflow-hidden",
              isImporting ? "border-yellow-400" : "border-white"
            )}
          >
            <Upload size={16} />
            <span>Import</span>
          </div>
          <div
            className={cn(
              "px-3 py-1 rounded flex items-center space-x-2 border-1 relative overflow-hidden",
              isDerivingUnits ? "border-yellow-400" : "border-transparent"
            )}
            style={
              isDerivingUnits && unitsPct !== null
                ? { backgroundImage: `linear-gradient(to right, rgba(250, 204, 21, 0.25) ${unitsPct}%, transparent ${unitsPct}%)` }
                : undefined
            }
          >
            <Search size={16} />
            <span>Statistical Units</span>
          </div>
          <div
            className={cn(
              "px-3 py-1 rounded flex items-center space-x-2 border-1 relative overflow-hidden",
              isDerivingReports ? "border-yellow-400" : "border-transparent"
            )}
            style={
              isDerivingReports && reportsPct !== null
                ? { backgroundImage: `linear-gradient(to right, rgba(250, 204, 21, 0.25) ${reportsPct}%, transparent ${reportsPct}%)` }
                : undefined
            }
          >
            <BarChartHorizontal size={16} />
            <span>Reports</span>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-1">Live status with progress indicators</p>

        {/* Progress details */}
        {(isDerivingUnits || isDerivingReports) && (
          <div className="mt-2 space-y-1">
            {derivingUnits?.active && derivingUnits.progress.map((step) => (
              <div key={step.step} className="flex items-center space-x-2 text-xs">
                <span className="text-gray-600 min-w-[180px]">{step.step}</span>
                <Progress value={step.total > 0 ? (step.completed / step.total) * 100 : 0} className="h-1.5 flex-1" />
                <span className="text-gray-500">{step.completed}/{step.total}</span>
              </div>
            ))}
            {derivingReports?.active && derivingReports.progress.map((step) => (
              <div key={step.step} className="flex items-center space-x-2 text-xs">
                <span className="text-gray-600 min-w-[180px]">{step.step}</span>
                <Progress value={step.total > 0 ? (step.completed / step.total) * 100 : 0} className="h-1.5 flex-1" />
                <span className="text-gray-500">{step.completed}/{step.total}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
