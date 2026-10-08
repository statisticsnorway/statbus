"use client";

import { useState } from "react";
import { buttonVariants } from "@/components/ui/button";
import { Download, Loader2, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAtomValue } from "jotai";
import { searchResultAtom, derivedApiSearchParamsAtom } from "@/atoms/search";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Progress } from "@/components/ui/progress";
import {
  EXCEL_CONFIRM_ROWS,
  EXCEL_MAX_DATA_ROWS,
  exportBaseName,
} from "@/app/search/export/export-query";
import {
  formatExportProgress,
  isExportActive,
  useStatisticalUnitExport,
} from "@/app/search/export/use-statistical-unit-export";

function formatRowCount(n: number): string {
  return n.toLocaleString("en-US").replace(/,/g, " ");
}

/**
 * Search result export (STATBUS-421). One streaming request to the server's
 * COPY export route (`/api/search/export`, the user's own role), written to
 * disk as it arrives, with row and byte progress, cancellation, and honest
 * failure reporting: an incomplete export is never saved.
 */
export function ExportCSVLink() {
  const searchResult = useAtomValue(searchResultAtom);
  const searchParams = useAtomValue(derivedApiSearchParamsAtom);
  const { progress, startExport, cancelExport } = useStatisticalUnitExport();
  const [confirmLargeXlsx, setConfirmLargeXlsx] = useState(false);

  if (!searchResult?.total) {
    return null;
  }

  const total = searchResult.total;
  const filenameBase = exportBaseName(searchParams.get("unit_type"));

  const begin = (format: "csv" | "xlsx") =>
    startExport({
      format,
      searchParams,
      filenameBase,
      expectedTotal: total,
      totalIsExact: !searchResult.countIsEstimate,
    });

  const onCsvClick = () => void begin("csv");
  const onXlsxClick = () => {
    if (total > EXCEL_CONFIRM_ROWS) {
      setConfirmLargeXlsx(true);
    } else {
      void begin("xlsx");
    }
  };

  if (isExportActive(progress)) {
    const percent =
      progress.expectedRows != null && progress.expectedRows > 0
        ? Math.min(100, (progress.rowsReceived / progress.expectedRows) * 100)
        : null;
    return (
      <div className="flex items-center gap-2">
        <div className="flex flex-col gap-1">
          <span className="text-xs text-gray-500">
            <Loader2 className="inline h-3 w-3 mr-1 animate-spin" />
            {formatExportProgress(progress)}
          </span>
          {percent != null && <Progress value={percent} className="h-1 w-48" />}
        </div>
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
      <div className="flex items-center gap-2">
        <span
          className="text-xs text-red-600 max-w-80"
          title={progress.error}
          role="alert"
        >
          {formatExportProgress(progress)}
        </span>
        <button
          onClick={cancelExport}
          className="text-gray-400 hover:text-gray-600"
          title="Dismiss"
        >
          <X className="h-3 w-3" />
        </button>
      </div>
    );
  }

  const excelUnavailable = total > EXCEL_MAX_DATA_ROWS;

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          className={cn(
            buttonVariants({ variant: "secondary", size: "sm" }),
            "flex items-center space-x-2"
          )}
        >
          <Download size={17} />
          <span>Export</span>
          {progress.phase === "complete" && (
            <span className="text-xs text-green-600 ml-1">
              {formatExportProgress(progress)}
            </span>
          )}
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={onCsvClick}>
            Download CSV ({formatRowCount(total)} rows)
          </DropdownMenuItem>
          {excelUnavailable ? (
            <DropdownMenuItem
              disabled
              title="Excel row limit exceeded. Use CSV instead."
            >
              Excel unavailable (over {formatRowCount(EXCEL_MAX_DATA_ROWS)}{" "}
              rows). Use CSV
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem onClick={onXlsxClick}>
              Download Excel (.xlsx)
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <AlertDialog open={confirmLargeXlsx} onOpenChange={setConfirmLargeXlsx}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Large Excel export</AlertDialogTitle>
            <AlertDialogDescription>
              This export has {formatRowCount(total)} rows. Excel struggles to
              open workbooks above {formatRowCount(EXCEL_CONFIRM_ROWS)} rows —
              the workbook is built in your browser and may take minutes and use
              a lot of memory. CSV is recommended for large exports.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Use CSV instead</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                setConfirmLargeXlsx(false);
                void begin("xlsx");
              }}
            >
              Build Excel anyway
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
