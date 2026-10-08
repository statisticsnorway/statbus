"use client";

/**
 * Streaming statistical-unit export (STATBUS-421).
 *
 * BOTH formats make ONE request to `/api/search/export`, the server route
 * that streams `COPY (SELECT ...) TO STDOUT` as the user's own database role.
 *
 * - CSV: the response is written chunk by chunk to a file the user chose with
 *   showSaveFilePicker (straight to disk, flat memory) or, where no picker
 *   exists, collected and handed to a normal download.
 * - XLSX: the same CSV stream is converted to a workbook WHILE it arrives, in
 *   a dedicated Worker (xlsx-stream.ts, ported from the measured prototype),
 *   and the workbook bytes go to the same kind of file. There is no
 *   conversion step after the transfer: the last network byte is followed by
 *   the ZIP's central directory and nothing else.
 *
 * - Progress: bytes received and rows received (quote-aware CSV record
 *   counter) against the exact total the server announces in
 *   `X-Export-Total-Rows` (counted in the same snapshot as the COPY).
 * - Integrity: the file is committed only when the records received equal
 *   that total; any shortfall, network failure, server abort or Excel
 *   refusal calls abort() on the file, so a partial export is never saved.
 * - Excel limit: a sheet holds 1,048,576 rows INCLUDING the header, so at
 *   most EXCEL_MAX_DATA_ROWS (1,048,575) data rows. Refused before the
 *   request against the search total, by the route (max_rows -> 413) against
 *   its exact count, and by the writer on the fly.
 * - Observability: the server logs every failure with rows sent, expected
 *   rows, bytes and elapsed time; the client additionally reports failures
 *   (and completions of large exports) to /api/logger.
 */

import { useCallback, useRef, useState } from "react";
import { baseDataStore } from "@/context/BaseDataStore";
import { EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";
import { EXCEL_CONFIRM_ROWS } from "./export-query";
import { EXPORT_TOTAL_ROWS_HEADER } from "./export-sql";
import {
  canPickSaveFile,
  createMemorySink,
  createWritableSink,
  EXPORT_FILE_TYPES,
  ExportCancelledError,
  ExportIncompleteError,
  ExportRefusedError,
  ExportStreamError,
  excelRowLimitError,
  exportRequestUrl,
  parseAnnouncedTotal,
  pickSaveFile,
  pumpExportToSink,
  requestFailureMessage,
  type ExportFormat,
  type ExportSink,
} from "./export-download";
import { createXlsxSink, exportFieldTypes } from "./xlsx-stream";
import { createXlsxConverter } from "./create-xlsx-worker";
import { reportExportEvent } from "./export-logger";

export type { ExportFormat };

export interface SearchExportProgress {
  phase: "idle" | "waiting" | "downloading" | "complete" | "error";
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
  /** The search page's total, for progress until the server announces. */
  expectedTotal: number | null;
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
    if (typeof parsed?.message === "string") return parsed.message;
  } catch {
    // Not JSON; fall through to the raw text.
  }
  return text || response.statusText;
}

function formatMegabytes(bytes: number): string {
  return `${(bytes / 1_000_000).toFixed(1)} MB`;
}

/** True when the export is still running (show progress and Cancel). */
export function isExportActive(progress: SearchExportProgress): boolean {
  return progress.phase === "waiting" || progress.phase === "downloading";
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function useStatisticalUnitExport() {
  const [progress, setProgress] = useState<SearchExportProgress>(IDLE);
  const abortRef = useRef<AbortController | null>(null);

  const cancelExport = useCallback(() => {
    abortRef.current?.abort();
    setProgress(IDLE);
  }, []);

  const startExport = useCallback(async (options: StartExportOptions) => {
    const { format, searchParams, filenameBase, expectedTotal } = options;
    const fileType = EXPORT_FILE_TYPES[format];
    const filename = `${filenameBase}${fileType.extension}`;

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const startTime = Date.now();

    // The one URL whose failure/success is reported to the server log; it
    // identifies the export completely (filters + order + format).
    const requestUrl = exportRequestUrl(searchParams, format);
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

    // An Excel export the search total already rules out is refused before
    // the save dialog and before any request.
    if (format === "xlsx") {
      const tooLarge = excelRowLimitError(expectedTotal);
      if (tooLarge) {
        fail(tooLarge, 0, 0);
        return;
      }
    }

    let sink: ExportSink | null = null;
    try {
      // The save dialog needs the click's user activation, so it is the
      // FIRST await. Where there is no picker (Firefox, Safari) the file is
      // collected and handed to a normal download at the end.
      const file: ExportSink = canPickSaveFile()
        ? createWritableSink(
            await (
              await pickSaveFile(
                filename,
                fileType.description,
                fileType.mime,
                fileType.extension
              )
            ).createWritable(),
            "file-picker"
          )
        : createMemorySink(
            filename,
            format === "csv" ? `${fileType.mime};charset=utf-8` : fileType.mime
          );
      if (format === "xlsx") {
        const { statDefinitions } = await baseDataStore.getBaseData();
        sink = createXlsxSink(
          file,
          createXlsxConverter({
            fieldTypes: exportFieldTypes(
              statDefinitions.map(({ code }) => code).filter(isString)
            ),
            maxDataRows: EXCEL_MAX_DATA_ROWS,
          })
        );
      } else {
        sink = file;
      }
      const activeSink = sink;
      controller.signal.addEventListener(
        "abort",
        () => void activeSink.abort(new ExportCancelledError()).catch(() => {}),
        { once: true }
      );

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
          requestFailureMessage(
            response.status,
            await responseErrorText(response)
          ),
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
    } catch (error) {
      await sink?.abort(error).catch(() => {});
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
      if (error instanceof ExportRefusedError) {
        fail(error.message, latestRows, latestBytes);
        return;
      }
      fail(describe(error), latestRows, latestBytes);
    }
  }, []);

  return { progress, startExport, cancelExport };
}

function isString(value: string | null | undefined): value is string {
  return typeof value === "string";
}
