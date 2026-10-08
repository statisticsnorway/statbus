"use client";

/**
 * Streaming statistical-unit export (STATBUS-421).
 *
 * ONE request to PostgREST per export — the browser calls
 * `/rest/statistical_unit` directly with `Accept: text/csv` (CSV) or
 * `Accept: application/json` (XLSX, built client-side so a large workbook
 * can never exhaust the shared app container's memory). This replaces the
 * old `/api/search/export` page loop, which repeated `count=exact` and a
 * deep-OFFSET sort per 100k rows until a page crossed the 120 s statement
 * timeout and the download died silently at a page boundary.
 *
 * - Progress: rows received (quote-aware CSV record counter) against the
 *   total the search page already displays.
 * - Integrity: the request sends `Prefer: count=exact`, so PostgREST
 *   announces the exact total of THIS response in `Content-Range`
 *   (`0-1976462/1976463`). A CSV whose row count differs from it is
 *   reported as an error and never saved. Only when that header carries no
 *   total does the guard fall back to the search page's total, and only if
 *   that total is exact (a planner estimate cannot judge completeness).
 * - Observability: failures (and completions of large exports) are reported
 *   to /api/logger with the request URL, row counts and elapsed time, so a
 *   failed export is findable in the server logs afterwards.
 */

import { useCallback, useRef, useState } from "react";
import {
  fetchWithAuthRefresh,
  getBrowserRestClient,
} from "@/context/RestClientStore";
import { baseDataStore } from "@/context/BaseDataStore";
import { describeError } from "@/lib/error-format";
import {
  composeExportSearchParams,
  exportFieldNames,
  EXCEL_MAX_DATA_ROWS,
  EXCEL_CONFIRM_ROWS,
} from "./export-query";
import { createCsvRowCounter } from "./csv-row-counter";
import {
  EXACT_COUNT_PREFER,
  exportIncompleteError,
  parseContentRangeTotal,
  resolveExpectedRows,
} from "./export-completeness";
import { reportExportEvent } from "./export-logger";

export type ExportFormat = "csv" | "xlsx";

export interface SearchExportProgress {
  phase: "idle" | "downloading" | "processing" | "complete" | "error";
  rowsReceived: number;
  bytesReceived: number;
  /** Total the search page displays; null when no count is available. */
  expectedRows: number | null;
  elapsedMs: number;
  error?: string;
}

export interface StartExportOptions {
  format: ExportFormat;
  /** The search page's API params (filters and order). */
  searchParams: URLSearchParams;
  /** Download filename without extension, e.g. "establishments". */
  filenameBase: string;
  expectedTotal: number | null;
  /** True when expectedTotal is an exact count, not a planner estimate. */
  totalIsExact: boolean;
}

const IDLE: SearchExportProgress = {
  phase: "idle",
  rowsReceived: 0,
  bytesReceived: 0,
  expectedRows: null,
  elapsedMs: 0,
};

/** Completions at or above this size are logged (info) for timing measurement. */
const COMPLETION_LOG_ROWS = EXCEL_CONFIRM_ROWS;

const DATE_FIELDS = new Set(["birth_date", "death_date"]);
const PROGRESS_UPDATE_INTERVAL_MS = 100;

function formatCount(n: number): string {
  return n.toLocaleString("en-US").replace(/,/g, " ");
}

export function formatExportProgress(progress: SearchExportProgress): string {
  const seconds = Math.floor(progress.elapsedMs / 1000);
  const elapsed =
    seconds < 60
      ? `${seconds}s`
      : `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  const ofTotal =
    progress.expectedRows != null
      ? ` of ${formatCount(progress.expectedRows)}`
      : "";
  switch (progress.phase) {
    case "downloading":
      return `Downloading… ${formatCount(progress.rowsReceived)}${ofTotal} rows (${elapsed})`;
    case "processing":
      return `Building Excel workbook… ${formatCount(progress.rowsReceived)} rows (${elapsed})`;
    case "complete":
      return `Downloaded ${formatCount(progress.rowsReceived)} rows in ${elapsed}`;
    case "error":
      return progress.error || "Export failed";
    default:
      return "";
  }
}

function saveBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}

export function useStatisticalUnitExport() {
  const [progress, setProgress] = useState<SearchExportProgress>(IDLE);
  const abortRef = useRef<AbortController | null>(null);

  const cancelExport = useCallback(() => {
    abortRef.current?.abort();
    setProgress(IDLE);
  }, []);

  const startExport = useCallback(async (options: StartExportOptions) => {
    const { format, searchParams, filenameBase, expectedTotal, totalIsExact } =
      options;

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const startTime = Date.now();

    // The one URL whose failure/success is reported to the server log; it
    // identifies the export completely (filters + select + order).
    let requestUrl = "(url not yet composed)";
    // Local tallies so the catch below never reads stale React state.
    let latestRows = 0;
    let latestBytes = 0;
    // The search page's total until the server announces the exact one.
    let expectedRows = expectedTotal;

    const fail = (
      error: string,
      rowsReceived: number,
      bytesReceived: number
    ) => {
      const elapsedMs = Date.now() - startTime;
      setProgress({
        phase: "error",
        rowsReceived,
        bytesReceived,
        expectedRows,
        elapsedMs,
        error,
      });
      void reportExportEvent("error", `Search export failed: ${error}`, {
        format,
        url: requestUrl,
        rowsReceived,
        expectedRows,
        bytesReceived,
        elapsedMs,
        error,
      });
    };

    const succeed = (rowsReceived: number, bytesReceived: number) => {
      const elapsedMs = Date.now() - startTime;
      setProgress({
        phase: "complete",
        rowsReceived,
        bytesReceived,
        expectedRows,
        elapsedMs,
      });
      if (rowsReceived >= COMPLETION_LOG_ROWS) {
        void reportExportEvent(
          "info",
          `Search export completed: ${rowsReceived} rows as ${format}`,
          {
            format,
            url: requestUrl,
            rowsReceived,
            expectedRows,
            bytesReceived,
            elapsedMs,
          }
        );
      }
    };

    try {
      if (
        format === "xlsx" &&
        expectedTotal != null &&
        expectedTotal > EXCEL_MAX_DATA_ROWS
      ) {
        fail(
          `Excel supports at most ${formatCount(EXCEL_MAX_DATA_ROWS)} data rows; this export has ${formatCount(expectedTotal)}. Use CSV instead.`,
          0,
          0
        );
        return;
      }

      const client = await getBrowserRestClient();
      const baseData = await baseDataStore.getBaseData(client);
      const params = composeExportSearchParams(searchParams, baseData);
      const baseUrl = client.url.endsWith("/") ? client.url : `${client.url}/`;
      requestUrl = new URL(`statistical_unit?${params}`, baseUrl).toString();

      setProgress({
        phase: "downloading",
        rowsReceived: 0,
        bytesReceived: 0,
        expectedRows: expectedTotal,
        elapsedMs: 0,
      });

      const response = await fetchWithAuthRefresh(requestUrl, {
        method: "GET",
        signal: controller.signal,
        headers: {
          Accept: format === "csv" ? "text/csv" : "application/json",
          // The exact total of this very response, counted by the same
          // statement, in Content-Range: the completeness guard's reference.
          Prefer: EXACT_COUNT_PREFER,
        },
      });

      if (!response.ok) {
        const text = await response.text();
        let detail = text;
        try {
          const parsed = JSON.parse(text);
          detail = describeError(parsed);
        } catch {
          // Not JSON; keep the raw text.
        }
        fail(`Export request failed (${response.status}): ${detail}`, 0, 0);
        return;
      }

      const contentRange = response.headers.get("Content-Range");
      expectedRows = parseContentRangeTotal(contentRange) ?? expectedTotal;

      const reader = response.body?.getReader();
      if (!reader) {
        fail("Export response is not readable", 0, 0);
        return;
      }

      const chunks: Uint8Array[] = [];
      const counter = createCsvRowCounter();
      let bytesReceived = 0;
      let lastUpdate = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        bytesReceived += value.length;
        if (format === "csv") counter.push(value);
        latestBytes = bytesReceived;
        latestRows = format === "csv" ? counter.records : latestRows;

        const now = Date.now();
        if (now - lastUpdate > PROGRESS_UPDATE_INTERVAL_MS) {
          lastUpdate = now;
          setProgress({
            phase: "downloading",
            rowsReceived: format === "csv" ? counter.records : 0,
            bytesReceived,
            expectedRows,
            elapsedMs: now - startTime,
          });
        }
      }

      if (format === "csv") {
        const rowsReceived = counter.records;
        // A short stream is a failed export, not a file: the historical bugs
        // were exactly silent partial downloads.
        const incomplete = exportIncompleteError(
          rowsReceived,
          resolveExpectedRows(contentRange, expectedTotal, totalIsExact)
        );
        if (incomplete) {
          fail(incomplete, rowsReceived, bytesReceived);
          return;
        }
        saveBlob(
          new Blob(chunks as BlobPart[], { type: "text/csv;charset=utf-8" }),
          `${filenameBase}.csv`
        );
        succeed(rowsReceived, bytesReceived);
        return;
      }

      // XLSX: parse the JSON rows and build the workbook in the browser.
      const rowsText = await new Blob(chunks as BlobPart[]).text();
      const rows = JSON.parse(rowsText) as Record<string, unknown>[];
      latestRows = rows.length;

      setProgress({
        phase: "processing",
        rowsReceived: rows.length,
        bytesReceived,
        expectedRows,
        elapsedMs: Date.now() - startTime,
      });

      const incomplete = exportIncompleteError(
        rows.length,
        resolveExpectedRows(contentRange, expectedTotal, totalIsExact)
      );
      if (incomplete) {
        fail(incomplete, rows.length, bytesReceived);
        return;
      }

      if (rows.length > EXCEL_MAX_DATA_ROWS) {
        fail(
          `Excel supports at most ${formatCount(EXCEL_MAX_DATA_ROWS)} data rows; this export has ${formatCount(rows.length)}. Use CSV instead.`,
          rows.length,
          bytesReceived
        );
        return;
      }

      const fields = exportFieldNames(baseData, searchParams.get("unit_type"));
      const { default: ExcelJS } = await import("@protobi/exceljs");
      const workbook = new ExcelJS.Workbook();
      const worksheet = workbook.addWorksheet("Data");
      worksheet.addRow(fields);
      for (let colIdx = 0; colIdx < fields.length; colIdx++) {
        if (DATE_FIELDS.has(fields[colIdx])) {
          worksheet.getColumn(colIdx + 1).numFmt = "yyyy-mm-dd";
        }
      }
      for (const record of rows) {
        worksheet.addRow(
          fields.map((field) => {
            const value = record[field];
            if (value === null || value === undefined) return null;
            if (DATE_FIELDS.has(field) && typeof value === "string") {
              // Append T00:00:00 so Date parses as local time, not UTC.
              // Without it, "2024-01-15" parses as UTC midnight and ExcelJS
              // converts to local time, which can shift the date by a day.
              const date = new Date(value + "T00:00:00");
              if (!isNaN(date.getTime())) return date;
              return value;
            }
            return value as string | number | boolean;
          })
        );
      }

      const buffer = await workbook.xlsx.writeBuffer();
      saveBlob(
        new Blob([buffer], {
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        }),
        `${filenameBase}.xlsx`
      );
      succeed(rows.length, bytesReceived);
    } catch (error) {
      if (controller.signal.aborted) return; // cancelled by the user
      fail(describeError(error), latestRows, latestBytes);
    }
  }, []);

  return { progress, startExport, cancelExport };
}
