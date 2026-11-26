"use client";

import type { ReactNode } from "react";
import {
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import { downloadMenuHeading, excelUnavailableReason } from "./download-menu-text";

/**
 * The choices of a Download menu (f69jcx): how many rows it downloads, stated once when known, then
 * CSV and Excel as equal choices. Excel is disabled, with the reason, when the rows exceed one sheet.
 * Used by the search, a unit's history and an import job's data.
 */
export function DownloadMenuContent({
  rows,
  onCsv,
  onExcel,
  extra,
}: {
  readonly rows?: number | null;
  readonly onCsv: () => void;
  readonly onExcel: () => void;
  /** Further choices after the formats, e.g. a chart's PNG. */
  readonly extra?: ReactNode;
}) {
  const heading = downloadMenuHeading(rows);
  const excelReason = excelUnavailableReason(rows);
  return (
    <DropdownMenuContent align="end" data-download-menu>
      {heading && (
        <>
          <DropdownMenuLabel className="font-normal text-zinc-500" data-download-rows>
            {heading}
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
        </>
      )}
      <DropdownMenuItem onClick={onCsv}>CSV</DropdownMenuItem>
      <DropdownMenuItem onClick={onExcel} disabled={excelReason !== null} title={excelReason ?? undefined}>
        Excel (.xlsx)
        {excelReason && <span className="ml-2 text-xs text-zinc-500">{excelReason}</span>}
      </DropdownMenuItem>
      {extra}
    </DropdownMenuContent>
  );
}
