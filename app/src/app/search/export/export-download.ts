/**
 * Client half of the streaming export (STATBUS-421 Phase 2): pump the export
 * response into a file sink while counting records, then commit the file only
 * when the received records equal the total the server announced.
 *
 * A sink is where the bytes land:
 *   - "file-picker": a FileSystemFileHandle the user chose with
 *     showSaveFilePicker (Chromium/Edge). Bytes go straight to disk through a
 *     FileSystemWritableFileStream, whose writes are staged and only become
 *     the file on close(); abort() leaves nothing behind. Flat memory.
 *   - "memory": the fallback where no picker exists; chunks are held and handed
 *     to a normal download on close().
 * Nothing is ever committed for an incomplete export: every failure path ends
 * in sink.abort().
 */

import { createCsvRowCounter } from "./csv-row-counter";
import { EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";

export type ExportFormat = "csv" | "xlsx";

export interface ExportSink {
  readonly kind: "file-picker" | "opfs" | "memory";
  write(chunk: Uint8Array): Promise<void>;
  /** Commit the file (the download/save happens here). */
  close(): Promise<void>;
  /** Discard everything written; never leaves a partial file. */
  abort(reason?: unknown): Promise<void>;
}

export interface PumpProgress {
  rowsReceived: number;
  bytesReceived: number;
  expectedRows: number;
}

export class ExportIncompleteError extends Error {
  constructor(
    readonly rowsReceived: number,
    readonly expectedRows: number,
    readonly bytesReceived: number
  ) {
    super(
      `Export incomplete: received ${formatCount(rowsReceived)} of ${formatCount(expectedRows)} rows. The file was not saved. Please try again.`
    );
    this.name = "ExportIncompleteError";
  }
}

/**
 * The file format cannot hold this export (e.g. Excel's sheet limit). Its
 * message is the honest refusal shown to the user as is, never wrapped as an
 * "interrupted" network failure.
 */
export class ExportRefusedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ExportRefusedError";
  }
}

/** A failure while streaming, carrying how far the export got. */
export class ExportStreamError extends Error {
  constructor(
    message: string,
    readonly rowsReceived: number,
    readonly expectedRows: number,
    readonly bytesReceived: number
  ) {
    super(message);
    this.name = "ExportStreamError";
  }
}

export function formatCount(n: number): string {
  return n.toLocaleString("en-US").replace(/,/g, " ");
}

/**
 * The refusal for an Excel export of `rows` data rows, or null when it fits.
 * One sheet holds 1,048,576 rows INCLUDING the header, so at most
 * EXCEL_MAX_DATA_ROWS (1,048,575) data rows. Checked before the request
 * against the search total and again against the rows actually received.
 */
export function excelRowLimitError(rows: number | null): string | null {
  if (rows == null || rows <= EXCEL_MAX_DATA_ROWS) return null;
  return `Excel supports at most ${formatCount(EXCEL_MAX_DATA_ROWS)} data rows; this export has ${formatCount(rows)}. Use CSV instead.`;
}

/**
 * The exact row count the export route announces in X-Export-Total-Rows, or
 * null when the header is missing or not a non-negative integer. Without a
 * trustworthy total there is nothing to check completeness against, so the
 * caller must refuse the export.
 */
export function parseAnnouncedTotal(header: string | null): number | null {
  // Number(null) and Number("") are 0, and Number("1e3") is 1000: only a
  // plain run of digits is a count.
  if (header == null || !/^\d+$/.test(header)) return null;
  const total = Number(header);
  return Number.isSafeInteger(total) ? total : null;
}

/**
 * Read `body` to the end, writing every chunk to `sink` and counting CSV
 * records. Resolves with the final tallies after `sink.close()` only when the
 * record count equals `expectedRows`; otherwise aborts the sink and rejects
 * with ExportIncompleteError (short or long stream) or ExportStreamError
 * (network/server failure mid-stream, or a sink write failure).
 */
export async function pumpExportToSink(
  body: ReadableStream<Uint8Array>,
  sink: ExportSink,
  expectedRows: number,
  onProgress?: (progress: PumpProgress) => void
): Promise<PumpProgress> {
  const reader = body.getReader();
  const counter = createCsvRowCounter();
  let bytesReceived = 0;
  const progress = (): PumpProgress => ({
    rowsReceived: counter.records,
    bytesReceived,
    expectedRows,
  });

  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      counter.push(value);
      bytesReceived += value.byteLength;
      await sink.write(value);
      onProgress?.(progress());
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    await sink.abort(error).catch(() => {});
    if (error instanceof ExportRefusedError) throw error;
    const message = error instanceof Error ? error.message : String(error);
    throw new ExportStreamError(
      `Export interrupted after ${formatCount(counter.records)} of ${formatCount(expectedRows)} rows: ${message}. The file was not saved.`,
      counter.records,
      expectedRows,
      bytesReceived
    );
  }

  if (counter.records !== expectedRows) {
    await sink.abort().catch(() => {});
    throw new ExportIncompleteError(
      counter.records,
      expectedRows,
      bytesReceived
    );
  }
  try {
    await sink.close();
  } catch (error) {
    // Finishing failed (e.g. the workbook could not be completed, or the
    // file could not be committed): discard rather than leave it half-made.
    await sink.abort(error).catch(() => {});
    throw error;
  }
  return progress();
}

/** File type per format: what the save dialog offers and the Blob carries. */
export const EXPORT_FILE_TYPES: Record<
  ExportFormat,
  { extension: string; mime: string; description: string }
> = {
  csv: { extension: ".csv", mime: "text/csv", description: "CSV file" },
  xlsx: {
    extension: ".xlsx",
    mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    description: "Excel workbook",
  },
};

/**
 * The export route URL for the search page's params. XLSX asks the route to
 * refuse (413, before a single row) when its exact count exceeds the sheet.
 */
export function exportRequestUrl(
  searchParams: URLSearchParams,
  format: ExportFormat
): string {
  const params = new URLSearchParams(searchParams);
  params.delete("limit");
  params.delete("offset");
  params.delete("max_rows");
  if (format === "xlsx") params.set("max_rows", String(EXCEL_MAX_DATA_ROWS));
  return `/api/search/export?${params}`;
}

/**
 * What the user reads when the route answers with an error. A 413 is the
 * route's honest refusal ("... at most N are allowed for this format. Use
 * CSV instead."), shown as is; anything else names the status.
 */
export function requestFailureMessage(status: number, detail: string): string {
  return status === 413
    ? detail
    : `Export request failed (${status}): ${detail}`;
}

/** Coalesce small network chunks into larger disk writes. */
const WRITE_BATCH_BYTES = 1 << 20;

interface WritableLike {
  // ArrayBuffer-backed (never shared) bytes, as FileSystemWritableFileStream
  // requires; flush() always writes a freshly allocated buffer.
  write(data: Uint8Array<ArrayBuffer>): Promise<void>;
  close(): Promise<void>;
  abort(reason?: unknown): Promise<void>;
}

/** A sink over a FileSystemWritableFileStream (picker or OPFS handle). */
export function createWritableSink(
  writable: WritableLike,
  kind: "file-picker" | "opfs",
  onClosed?: () => Promise<void>
): ExportSink {
  let batch: Uint8Array[] = [];
  let batchBytes = 0;
  const flush = async () => {
    if (batchBytes === 0) return;
    const merged = new Uint8Array(batchBytes);
    let offset = 0;
    for (const part of batch) {
      merged.set(part, offset);
      offset += part.byteLength;
    }
    batch = [];
    batchBytes = 0;
    await writable.write(merged);
  };
  return {
    kind,
    async write(chunk) {
      batch.push(chunk);
      batchBytes += chunk.byteLength;
      if (batchBytes >= WRITE_BATCH_BYTES) await flush();
    },
    async close() {
      await flush();
      await writable.close();
      await onClosed?.();
    },
    async abort(reason) {
      batch = [];
      batchBytes = 0;
      await writable.abort(reason);
    },
  };
}

/** Hand a Blob to the browser's normal download. */
export function saveBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  // Revoke after the download has had a chance to start.
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

/** The parts of the Origin Private File System the OPFS sink uses. */
export interface OpfsDirectory {
  getFileHandle(
    name: string,
    options?: { create?: boolean }
  ): Promise<{
    createWritable(): Promise<WritableLike>;
    getFile(): Promise<Blob>;
  }>;
  removeEntry(name: string): Promise<void>;
}

/** The OPFS root where the browser offers it with createWritable, else null. */
export async function opfsDirectory(): Promise<OpfsDirectory | null> {
  if (typeof navigator === "undefined" || !navigator.storage?.getDirectory)
    return null;
  if (
    typeof FileSystemFileHandle === "undefined" ||
    !("createWritable" in FileSystemFileHandle.prototype)
  )
    return null;
  try {
    return (await navigator.storage.getDirectory()) as unknown as OpfsDirectory;
  } catch {
    // e.g. a private window without storage access.
    return null;
  }
}

/**
 * Stream into the Origin Private File System, then hand the finished file to
 * a normal download (STATBUS-421 S4). The fallback where there is no save
 * picker (Firefox): memory stays flat while the
 * export streams, because the bytes go to disk, not to an array.
 *
 * close() commits the OPFS file, then downloads it. The File handed to the
 * download is disk-backed, so no RAM copy is made; the browser copies it to
 * Downloads, which is a measured one-off cost after completion (Firefox 142:
 * 7.7 s for a 117 MB workbook, 3.6 s at 500k rows). The OPFS entry is removed
 * after the download had time to start; abort() discards the bytes and
 * removes the entry at once, so a failed export leaves nothing behind.
 *
 * `onSaving` is called between the last byte and the hand-off, so the UI can
 * say "Saving file…" for that copy instead of looking stuck.
 */
export async function createOpfsSink(
  root: OpfsDirectory,
  filename: string,
  options: {
    onSaving?: () => void;
    download?: (file: Blob, filename: string) => void;
    removeAfterMs?: number;
  } = {}
): Promise<ExportSink> {
  const { onSaving, download = saveBlob, removeAfterMs = 60_000 } = options;
  // Unique per export, so two exports never write into one entry.
  const entry = `statbus-export-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const handle = await root.getFileHandle(entry, { create: true });
  const remove = () => root.removeEntry(entry).catch(() => {});
  const writable = createWritableSink(
    await handle.createWritable(),
    "opfs",
    async () => {
      onSaving?.();
      download(await handle.getFile(), filename);
      setTimeout(() => void remove(), removeAfterMs);
    }
  );
  return {
    kind: "opfs",
    write: (chunk) => writable.write(chunk),
    close: () => writable.close(),
    async abort(reason) {
      await writable.abort(reason).catch(() => {});
      await remove();
    },
  };
}

/** Last-resort sink: hold the chunks, download them as one Blob on close. */
export function createMemorySink(
  filename: string,
  mimeType: string
): ExportSink {
  let chunks: Uint8Array[] = [];
  return {
    kind: "memory",
    async write(chunk) {
      chunks.push(chunk);
    },
    async close() {
      saveBlob(new Blob(chunks as BlobPart[], { type: mimeType }), filename);
      chunks = [];
    },
    async abort() {
      chunks = [];
    },
  };
}

interface SaveFilePickerOptions {
  suggestedName?: string;
  types?: Array<{ description: string; accept: Record<string, string[]> }>;
}

type ShowSaveFilePicker = (
  options?: SaveFilePickerOptions
) => Promise<FileSystemFileHandle>;

/** True where the user can choose a file that the export streams into. */
export function canPickSaveFile(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof (window as unknown as { showSaveFilePicker?: unknown })
      .showSaveFilePicker === "function"
  );
}

export class ExportCancelledError extends Error {
  constructor() {
    super("Export cancelled");
    this.name = "ExportCancelledError";
  }
}

/**
 * Ask the user where to save. MUST be called directly from the click handler
 * (before any other await): the picker requires transient user activation.
 * Rejects with ExportCancelledError if the user dismisses the dialog.
 */
export async function pickSaveFile(
  suggestedName: string,
  description: string,
  mimeType: string,
  extension: string
): Promise<FileSystemFileHandle> {
  const picker = (
    window as unknown as { showSaveFilePicker: ShowSaveFilePicker }
  ).showSaveFilePicker;
  try {
    return await picker({
      suggestedName,
      types: [{ description, accept: { [mimeType]: [extension] } }],
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ExportCancelledError();
    }
    throw error;
  }
}
