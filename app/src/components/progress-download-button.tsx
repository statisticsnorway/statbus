"use client";

import React from "react";
import { Download, Loader2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { useProgressDownload, formatDownloadProgress } from "@/hooks/use-progress-download";
import { DownloadMenuContent } from "@/components/download-menu";

interface ProgressDownloadButtonProps {
  slug: string;
  filter: string;
  /** Row count for this filter — Excel option disabled when > 1M */
  rowCount?: number;
  variant?: "default" | "ghost";
  className?: string;
}

/**
 * Download button for an import job's rows: the shared Download menu (row count once, CSV and Excel),
 * progress with Cancel while running, a notification when done (f69jcx).
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

  if (progress.phase === 'error') {
    return (
      <div className="flex items-center gap-1">
        <span className="text-xs text-red-600" title={progress.error} role="alert">
          {formatDownloadProgress(progress)}
        </span>
        <button onClick={cancelDownload} className="text-gray-400 hover:text-gray-600" title="Dismiss">
          <X className="h-3 w-3" />
        </button>
      </div>
    );
  }

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

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant={variant} size="sm" className={className} title="Download">
          <Download className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DownloadMenuContent
        rows={rowCount}
        onCsv={() => handleDownload('csv')}
        onExcel={() => handleDownload('xlsx')}
      />
    </DropdownMenu>
  );
}
