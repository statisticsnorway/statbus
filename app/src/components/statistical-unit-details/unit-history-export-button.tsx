"use client";

import { buttonVariants } from "@/components/ui/button";
import { Download, Loader2, X } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  formatExportProgress,
  isExportActive,
  useStatisticalUnitExport,
} from "@/app/search/export/use-statistical-unit-export";

/**
 * Export the temporal history of one unit. Uses the same streaming export
 * route as the search page (STATBUS-421); a unit's history is
 * small, so no confirmation gates apply.
 */
export function UnitHistoryExportButton({
  unitId,
  unitType,
}: {
  readonly unitId: number;
  readonly unitType: string;
}) {
  const { progress, startExport, cancelExport } = useStatisticalUnitExport();

  const begin = (format: "csv" | "xlsx") => {
    const params = new URLSearchParams({
      unit_id: `eq.${unitId}`,
      unit_type: `in.(${unitType})`,
      order: "valid_from.asc",
    });
    void startExport({
      format,
      searchParams: params,
      filenameBase: `unit_${unitId}_history`,
      expectedTotal: null,
    });
  };

  if (isExportActive(progress)) {
    return (
      <div className="flex items-center gap-1">
        <span className="text-xs text-gray-500">
          <Loader2 className="inline h-3 w-3 mr-1 animate-spin" />
          {formatExportProgress(progress)}
        </span>
        <button
          onClick={cancelExport}
          className="text-gray-400 hover:text-gray-600"
          title="Cancel export"
        >
          <X className="h-3 w-3" />
        </button>
      </div>
    );
  }

  if (progress.phase === "error") {
    return (
      <span
        className="text-xs text-red-600"
        title={progress.error}
        role="alert"
      >
        {formatExportProgress(progress)}
      </span>
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          buttonVariants({ variant: "outline", size: "sm" }),
          "flex items-center space-x-2"
        )}
      >
        <Download size={17} />
        <span>Export unit history</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => begin("csv")}>
          Download CSV
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => begin("xlsx")}>
          Download XLSX
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
