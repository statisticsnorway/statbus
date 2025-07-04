"use client";

import { cn } from "@/lib/utils";
import { BarChartHorizontal, Search, Upload } from "lucide-react";
import { useWorkerStatus } from "@/atoms/worker-status";

export function NavbarStatusVisualizer() {
  const workerStatus = useWorkerStatus();
  const { isImporting, isDerivingUnits, isDerivingReports } = workerStatus;

  // Create a simplified version of the navbar for visualization
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

      {/* Processing states */}
      <div className="bg-white p-3 rounded-md">
        <h3 className="text-sm font-medium mb-2">During Processing</h3>
        <div className="bg-ssb-dark text-white p-2 rounded-md flex justify-center space-x-3">
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1 border-yellow-400",
          )}>
            <Upload size={16} />
            <span>Import</span>
          </div>
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1 border-yellow-400",
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
        <p className="text-xs text-gray-500 mt-1">Yellow borders indicate active processing</p>
      </div>

      {/* Current system state */}
      <div className="bg-white p-3 rounded-md">
        <h3 className="text-sm font-medium mb-2">Current System State</h3>
        <div className="bg-ssb-dark text-white p-2 rounded-md flex justify-center space-x-3">
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1",
            isImporting ? "border-yellow-400" : "border-white"
          )}>
            <Upload size={16} />
            <span>Import</span>
          </div>
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1",
            isDerivingUnits ? "border-yellow-400" : "border-transparent"
          )}>
            <Search size={16} />
            <span>Statistical Units</span>
          </div>
          <div className={cn(
            "px-3 py-1 rounded flex items-center space-x-2 border-1",
            isDerivingReports ? "border-yellow-400" : "border-transparent"
          )}>
            <BarChartHorizontal size={16} />
            <span>Reports</span>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-1">Live status based on current system state</p>
      </div>
    </div>
  );
}
