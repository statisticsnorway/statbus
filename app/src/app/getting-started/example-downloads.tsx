"use client";

import React from "react";
import { downloadCsvAsExcel } from "./upload-excel";

/**
 * An example file as CSV and as Excel, side by side (owner 2026-11-26: everybody uses Excel). The
 * Excel file is made in the browser from the CSV, so both hold the same rows.
 */
export function ExampleDownloads({ csvHref, label }: { csvHref: string; label: string }) {
  const base = csvHref.split("/").pop()!.replace(/\.csv$/, "");
  const [error, setError] = React.useState<string | null>(null);
  return (
    <span className="inline-flex flex-wrap items-center gap-x-2" data-example-downloads={base}>
      <span>{label}:</span>
      <a href={csvHref} download={`${base}.csv`} className="underline">
        CSV
      </a>
      <button
        type="button"
        className="underline"
        onClick={() => {
          setError(null);
          downloadCsvAsExcel(csvHref, `${base}.xlsx`).catch((e) => setError(e instanceof Error ? e.message : String(e)));
        }}
      >
        Excel
      </button>
      {error && <span className="text-red-700">The download failed: {error}</span>}
    </span>
  );
}
