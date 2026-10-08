"use client";

/**
 * Streaming statistical-unit export (STATBUS-421).
 *
 * CSV (Phase 2): ONE request to `/api/search/export`, the server route that
 * streams `COPY (SELECT ...) TO STDOUT` as the user's own database role. The
 * response is written chunk by chunk to a file the user chose with
 * showSaveFilePicker (straight to disk, flat memory) or, where no picker
 * exists, collected and handed to a normal download.
 *
 * - Progress: bytes received and rows received (quote-aware CSV record
 *   counter) against the exact total the server announces in
 *   `X-Export-Total-Rows` (counted in the same snapshot as the COPY).
 * - Integrity: the file is committed only when the records received equal
 *   that total; any shortfall, network failure or server abort calls
 *   abort() on the file, so a partial export is never saved.
 * - Observability: the server logs every failure with rows sent, expected
 *   rows, bytes and elapsed time; the client additionally reports failures
 *   (and completions of large exports) to /api/logger.
 *
 * XLSX still reads JSON from `/rest` and builds the workbook in memory until
 * STATBUS-421 S3 replaces it with a streaming Worker fed by the same route.
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
import { EXPORT_TOTAL_ROWS_HEADER } from "./export-sql";
import {
  canPickSaveFile,
  createMemorySink,
  createWritableSink,
  ExportCancelledError,
  ExportIncompleteError,
  ExportStreamError,
  excelRowLimitError,
  parseAnnouncedTotal,
  pickSaveFile,
  pumpExportToSink,
  saveBlob,
  type ExportSink,
} from "./export-download";
import {
  EXACT_COUNT_PREFER,
  exportIncompleteError,
  parseContentRangeTotal,
  resolveExpectedRows,
} from "./export-completeness";
import { reportExportEvent } from "./export-logger";

export type ExportFormat = "csv" | "xlsx";

export interface SearchExportProgress {
  phase:
    | "idle"
    | "waiting"
    | "downloading"
    | "processing"
    | "complete"
    | "error";
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
    case "waiting":
      return `Preparing export… (${elapsed})`;
    case "downloading":
      return `Downloading… ${formatCount(progress.rowsReceived)}${ofTotal} rows, ${formatMegabytes(progress.bytesReceived)} (${elapsed})`;
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

/** The JSON `message` of a failed response, or its raw text. */
async function responseErrorText(response: Response): Promise<string> {
  const text = await response.text().catch(() => "");
  try {
    const parsed = JSON.parse(text);
    return typeof parsed?.message === "string"
      ? parsed.message
      : describeError(parsed);
  } catch {
    return text || response.statusText;
  }
}

function formatMegabytes(bytes: number): string {
  return `${(bytes / 1_000_000).toFixed(1)} MB`;
}

const CSV_MIME = "text/csv";

/** True when the export is still running (show progress and Cancel). */
export function isExportActive(progress: SearchExportProgress): boolean {
  return (
    progress.phase === "waiting" ||
    progress.phase === "downloading" ||
    progress.phase === "processing"
  );
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
      if (format === "csv") {
        // The save dialog needs the click's user activation, so it is the
        // FIRST await. Where there is no picker (Firefox, Safari) the CSV is
        // collected and handed to a normal download at the end.
        const sink: ExportSink = canPickSaveFile()
          ? createWritableSink(
              await (
                await pickSaveFile(
                  `${filenameBase}.csv`,
                  "CSV file",
                  CSV_MIME,
                  ".csv"
                )
              ).createWritable(),
              "file-picker"
            )
          : createMemorySink(
              `${filenameBase}.csv`,
              `${CSV_MIME};charset=utf-8`
            );
        controller.signal.addEventListener(
          "abort",
          () => void sink.abort(new ExportCancelledError()).catch(() => {}),
          { once: true }
        );

        const params = new URLSearchParams(searchParams);
        params.delete("limit");
        params.delete("offset");
        requestUrl = `/api/search/export?${params}`;
        setProgress({
          phase: "waiting",
          rowsReceived: 0,
          bytesReceived: 0,
          expectedRows: expectedTotal,
          elapsedMs: 0,
        });
        const ticker = setInterval(
          () =>
            setProgress((current) =>
              current.phase === "waiting"
                ? { ...current, elapsedMs: Date.now() - startTime }
                : current
            ),
          1000
        );
        let response: Response;
        try {
          response = await fetch(requestUrl, {
            signal: controller.signal,
            credentials: "same-origin",
          });
        } finally {
          clearInterval(ticker);
        }
        if (!response.ok || !response.body) {
          await sink.abort().catch(() => {});
          fail(
            `Export request failed (${response.status}): ${await responseErrorText(response)}`,
            0,
            0
          );
          return;
        }
        const announced = parseAnnouncedTotal(
          response.headers.get(EXPORT_TOTAL_ROWS_HEADER)
        );
        if (announced === null) {
          await response.body.cancel().catch(() => {});
          await sink.abort().catch(() => {});
          fail("Export response did not announce its row count", 0, 0);
          return;
        }
        expectedRows = announced;

        let lastUpdate = 0;
        const result = await pumpExportToSink(
          response.body,
          sink,
          announced,
          (pumped) => {
            latestRows = pumped.rowsReceived;
            latestBytes = pumped.bytesReceived;
            const now = Date.now();
            if (now - lastUpdate > PROGRESS_UPDATE_INTERVAL_MS) {
              lastUpdate = now;
              setProgress({
                phase: "downloading",
                rowsReceived: pumped.rowsReceived,
                bytesReceived: pumped.bytesReceived,
                expectedRows: announced,
                elapsedMs: now - startTime,
              });
            }
          }
        );
        succeed(result.rowsReceived, result.bytesReceived);
        return;
      }

      if (format === "xlsx") {
        const tooLarge = excelRowLimitError(expectedTotal);
        if (tooLarge) {
          fail(tooLarge, 0, 0);
          return;
        }
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
          Accept: "application/json",
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
      let bytesReceived = 0;
      let lastUpdate = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        bytesReceived += value.length;
        latestBytes = bytesReceived;

        const now = Date.now();
        if (now - lastUpdate > PROGRESS_UPDATE_INTERVAL_MS) {
          lastUpdate = now;
          setProgress({
            phase: "downloading",
            rowsReceived: 0,
            bytesReceived,
            expectedRows,
            elapsedMs: now - startTime,
          });
        }
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

      const tooLarge = excelRowLimitError(rows.length);
      if (tooLarge) {
        fail(tooLarge, rows.length, bytesReceived);
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
      // Cancelled by the user: either the Cancel button or the save dialog.
      if (controller.signal.aborted || error instanceof ExportCancelledError) {
        setProgress(IDLE);
        return;
      }
      if (
        error instanceof ExportStreamError ||
        error instanceof ExportIncompleteError
      ) {
        fail(error.message, error.rowsReceived, error.bytesReceived);
        return;
      }
      fail(describeError(error), latestRows, latestBytes);
    }
  }, []);

  return { progress, startExport, cancelExport };
}
