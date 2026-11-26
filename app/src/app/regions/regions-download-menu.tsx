"use client";

import React, { useState } from "react";
import { Download } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { DownloadMenuContent } from "@/components/download-menu";
import { fetchWithAuth, getBrowserRestClient } from "@/context/RestClientStore";
import { csvTextToExcelBlob, saveBlob } from "@/app/getting-started/upload-excel";
import { cn } from "@/lib/utils";

/**
 * The regions as the upload file (owner 2026-11-26, 5yxn4w): public.region_upload as CSV or Excel,
 * the columns the upload reads, so a person downloads the regions, edits them (names, coordinates)
 * and uploads the file again on Upload Regions, which checks it before storing. The menu is the
 * app's Download menu (f69jcx).
 */
export function RegionsDownloadMenu({ rows, className }: { rows?: number | null; className?: string }) {
  const [error, setError] = useState<string | null>(null);
  const download = async (excel: boolean) => {
    setError(null);
    try {
      const client = await getBrowserRestClient();
      const response = await fetchWithAuth(`${client.url}/region_upload`, { headers: { Accept: "text/csv" } });
      if (!response.ok) throw new Error(`${response.status} ${await response.text()}`);
      const csv = await response.text();
      if (excel) saveBlob(await csvTextToExcelBlob(csv, "Regions"), "regions.xlsx");
      else saveBlob(new Blob([csv], { type: "text/csv" }), "regions.csv");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };
  return (
    <span className={cn("inline-flex items-center gap-2", className)} data-regions-download="">
      <DropdownMenu>
        <DropdownMenuTrigger className={cn(buttonVariants({ variant: "outline", size: "sm" }), "flex items-center gap-1.5")}>
          <Download className="h-4 w-4" />
          Download
        </DropdownMenuTrigger>
        <DownloadMenuContent rows={rows} onCsv={() => void download(false)} onExcel={() => void download(true)} />
      </DropdownMenu>
      {error && <span className="text-sm text-red-700">The download failed: {error}</span>}
    </span>
  );
}
