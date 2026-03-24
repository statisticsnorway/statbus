"use client";

import React from "react";
import { Download, Loader2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useProgressDownload, formatDownloadProgress } from "@/hooks/use-progress-download";

const EXCEL_MAX_ROWS = 1_048_576;

interface ProgressDownloadButtonProps {
  slug: string;
  filter: string;
  /** Row count for this filter — Excel option disabled when > 1M */
  rowCount?: number;
  variant?: "default" | "ghost";
  className?: string;
}

/**
 * Download button with CSV/Excel format dropdown and progress tracking.
 * Replaces plain <a href> links with fetch-based downloads showing progress.
 */
export function ProgressDownloadButton({
  slug,
  filter,
  rowCount,
  variant = "ghost",
  className,
}: ProgressDownloadButtonProps) {
  const { progress, startDownload, cancelDownload } = useProgressDownload();

  const handleDownload = (format: 'csv' | 'xlsx') => {
    const url = `/api/import/download?slug=${encodeURIComponent(slug)}&filter=${encodeURIComponent(filter)}&format=${format}`;
    const filename = `${slug}-${filter}.${format}`;
    startDownload(url, filename);
  };

  const excelDisabled = rowCount != null && rowCount > EXCEL_MAX_ROWS;

  if (progress.phase === 'downloading') {
    return (
      <div className="flex items-center gap-1">
        <span className="text-xs text-gray-500 animate-pulse">
          <Loader2 className="inline h-3 w-3 mr-1 animate-spin" />
          {formatDownloadProgress(progress)}
        </span>
        <button onClick={cancelDownload} className="text-gray-400 hover:text-gray-600" title="Cancel download">
          <X className="h-3 w-3" />
        </button>
      </div>
    );
  }

  if (progress.phase === 'complete') {
    return (
      <span className="text-xs text-green-600">
        {formatDownloadProgress(progress)}
      </span>
    );
  }

  if (progress.phase === 'error') {
    return (
      <span className="text-xs text-red-600" title={progress.error}>
        Download failed
      </span>
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant={variant} size="sm" className={className}>
          <Download className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => handleDownload('csv')}>
          Download CSV
        </DropdownMenuItem>
        {excelDisabled ? (
          <DropdownMenuItem disabled>
            <span className="text-gray-400">Excel — exceeds ~1M row limit</span>
          </DropdownMenuItem>
        ) : (
          <DropdownMenuItem onClick={() => handleDownload('xlsx')}>
            Download Excel (.xlsx)
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
