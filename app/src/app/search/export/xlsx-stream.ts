/**
 * Streaming CSV -> XLSX conversion with flat memory (STATBUS-421 S3).
 *
 * Ported from the measured feasibility prototype (tmp/421-xlsx-proto,
 * streaming-xlsx.mjs): 1,048,575 data rows in 17.5 s in headless Chromium, a
 * 14 ms tail after the last network byte, under a 64 MB V8 heap cap; output
 * accepted by zipfile CRC, expat, openpyxl cell by cell, and LibreOffice.
 *
 * Pipeline:  CSV bytes --(TextDecoder stream)--> CSV records (quote-aware,
 *            embedded newlines, "" escapes, chunk boundaries)
 *            --> <row> XML --(TextEncoder)--> DEFLATE("xl/worksheets/sheet1.xml")
 *            --(fflate Zip, data-descriptor entries)--> output chunks --> sink
 *
 * Nothing is retained per row: the only state is the current partial CSV
 * record, the current XML batch, the deflate window, and the ZIP central
 * directory (7 entries). The sheet is compressed by the platform's native
 * CompressionStream("deflate-raw") where it exists, with fflate supplying only
 * the ZIP container and CRC-32; fflate's own DEFLATE is the fallback.
 *
 * The column order is the CSV header's: the export route defines it
 * explicitly, so the workbook and the CSV always agree.
 */

import { Zip, ZipDeflate, ZipPassThrough } from "fflate";
import { EXCEL_MAX_CELL_CHARS, EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";
import { ExportRefusedError, type ExportSink } from "./export-download";

export type XlsxColumnType = "string" | "number" | "date";
export type XlsxCompressor = "native" | "fflate";

export type ExcelRefusalCode = "row_limit" | "cell_too_long" | "zip64";

/** The workbook cannot be produced; the message tells the user what to do. */
export class ExcelRefusedError extends ExportRefusedError {
  constructor(
    message: string,
    readonly code: ExcelRefusalCode
  ) {
    super(message);
    this.name = "ExcelRefusedError";
  }
}

/** True where the native deflate-raw compressor exists. */
export function nativeDeflateRawAvailable(): boolean {
  try {
    new CompressionStream("deflate-raw" as CompressionFormat);
    return true;
  } catch {
    return false;
  }
}

/**
 * A ZIP entry compressed by the platform's native DEFLATE. fflate's Zip still
 * writes the container (local header, data descriptor, central directory) and
 * computes the CRC-32 over the uncompressed bytes in ZipPassThrough.push.
 * This is the subclassing path fflate documents for custom compression.
 */
class NativeZipDeflate extends ZipPassThrough {
  private readonly writer: WritableStreamDefaultWriter<BufferSource>;
  private last: Promise<void> | null = null;

  constructor(filename: string) {
    super(filename);
    this.compression = 8;
    const stream = new CompressionStream("deflate-raw" as CompressionFormat);
    this.writer = stream.writable.getWriter();
    const reader = stream.readable.getReader();
    void (async () => {
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          this.ondata(null, value, false);
        }
        this.ondata(null, new Uint8Array(0), true);
      } catch (error) {
        this.ondata(toFlateError(error), null as never, true);
      }
    })();
  }

  protected process(chunk: Uint8Array<ArrayBuffer>, final: boolean): void {
    // Writes are ordered. A write's promise settles once the transform has
    // consumed that chunk, so awaiting the LAST one (ready()) bounds the
    // uncompressed bytes in flight to what was pushed since the last await.
    if (chunk.length) {
      this.last = this.writer.write(chunk);
      this.last.catch((error) =>
        this.ondata(toFlateError(error), null as never, true)
      );
    }
    if (final)
      this.writer
        .close()
        .catch((error) =>
          this.ondata(toFlateError(error), null as never, true)
        );
  }

  ready(): Promise<void> {
    return this.last ?? Promise.resolve();
  }
}

function toFlateError(error: unknown) {
  const flateError = (
    error instanceof Error ? error : new Error(String(error))
  ) as Error & { code: number };
  flateError.code = flateError.code ?? -1;
  return flateError;
}

// fflate's Zip writer does not emit ZIP64 records, so every size and offset
// must stay below 4 GiB. The writer refuses rather than emitting a corrupt
// archive.
const ZIP32_LIMIT = 0xffffffff - 1024 * 1024;

// ---------------------------------------------------------------------------
// Streaming CSV record parser (same quote semantics as csv-row-counter.ts: a
// newline inside quotes is data, "" inside quotes is a literal quote, state
// carries across chunk boundaries, the last record may lack a \n).
// ---------------------------------------------------------------------------
export interface CsvRecordParser {
  push(chunk: Uint8Array): void;
  /** Flush the final record; throws if the input ended inside quotes. */
  end(): void;
}

export function createCsvRecordParser(
  onRecord: (record: string[]) => void
): CsvRecordParser {
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let fields: string[] = [];
  let field = "";
  let inQuotes = false;
  let quotePending = false; // saw a " inside quotes; next char decides
  let lineHasData = false;

  const endField = () => {
    fields.push(field);
    field = "";
  };
  const endRecord = () => {
    endField();
    const record = fields;
    fields = [];
    lineHasData = false;
    onRecord(record);
  };

  const feed = (s: string) => {
    let i = 0;
    const n = s.length;
    while (i < n) {
      if (quotePending) {
        quotePending = false;
        if (s.charCodeAt(i) === 34) {
          field += '"';
          i++;
          continue;
        }
        inQuotes = false; // closing quote; fall through to unquoted handling
      }
      if (inQuotes) {
        const q = s.indexOf('"', i);
        if (q === -1) {
          field += s.slice(i);
          return;
        }
        field += s.slice(i, q);
        i = q + 1;
        quotePending = true;
        continue;
      }
      // Unquoted: scan to the next delimiter.
      let j = i;
      while (j < n) {
        const c = s.charCodeAt(j);
        if (c === 44 || c === 10 || c === 34 || c === 13) break;
        j++;
      }
      if (j > i) {
        field += s.slice(i, j);
        lineHasData = true;
      }
      if (j === n) return;
      const c = s.charCodeAt(j);
      i = j + 1;
      if (c === 44) {
        lineHasData = true;
        endField();
      } else if (c === 10) {
        endRecord();
      } else if (c === 34) {
        inQuotes = true;
        lineHasData = true;
      } // c === 13 (CR before LF) is dropped
    }
  };

  return {
    push(chunk) {
      feed(decoder.decode(chunk, { stream: true }));
    },
    end() {
      feed(decoder.decode());
      if (quotePending) {
        quotePending = false;
        inQuotes = false;
      }
      if (inQuotes) throw new Error("CSV ended inside a quoted field");
      if (lineHasData || fields.length > 0) endRecord();
    },
  };
}

// ---------------------------------------------------------------------------
// Excel date serials.
// ---------------------------------------------------------------------------
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);

/**
 * The Excel (1900 date system) serial for an ISO date, or null when the value
 * must stay text: not a real calendar date, or before 1900 (which the 1900
 * system cannot represent).
 *
 * Excel keeps Lotus 1-2-3's fictitious 1900-02-29 as serial 60, so every date
 * BEFORE 1900-03-01 is one lower than the plain day count: 1900-01-01 -> 1,
 * 1900-02-28 -> 59, 1900-03-01 -> 61. Without that correction the prototype
 * found 29 Norway cells (1900-01-01 .. 1900-02-28, including the 1900-01-01
 * sentinel) reading back one day late.
 */
export function excelDateSerial(value: string): number | null {
  const match = DATE_RE.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1900) return null;
  const ms = Date.UTC(year, month - 1, day);
  const date = new Date(ms);
  // Date.UTC normalises 2024-02-30 to 2024-03-01: such a value is not a date.
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  const serial = Math.round((ms - EXCEL_EPOCH_MS) / 86_400_000);
  return serial <= 60 ? serial - 1 : serial;
}

// ---------------------------------------------------------------------------
// XLSX package parts. Minimal valid SpreadsheetML: no sharedStrings (strings
// are inlineStr, so no whole-file string table has to be held), no dimension
// (optional in CT_Worksheet, so the row count need not be known up front).
// ---------------------------------------------------------------------------
const XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
const NS_REL =
  "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const NS_PKG_REL =
  "http://schemas.openxmlformats.org/package/2006/relationships";

const STATIC_PARTS: ReadonlyArray<readonly [string, string]> = [
  [
    "[Content_Types].xml",
    XML_HEAD +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>' +
      "</Types>",
  ],
  [
    "_rels/.rels",
    XML_HEAD +
      `<Relationships xmlns="${NS_PKG_REL}">` +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>' +
      "</Relationships>",
  ],
  [
    "docProps/app.xml",
    XML_HEAD +
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>STATBUS</Application></Properties>',
  ],
  [
    "xl/workbook.xml",
    XML_HEAD +
      `<workbook xmlns="${NS_MAIN}" xmlns:r="${NS_REL}">` +
      '<sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>',
  ],
  [
    "xl/_rels/workbook.xml.rels",
    XML_HEAD +
      `<Relationships xmlns="${NS_PKG_REL}">` +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
      "</Relationships>",
  ],
  [
    "xl/styles.xml",
    XML_HEAD +
      `<styleSheet xmlns="${NS_MAIN}">` +
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/></numFmts>' +
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="3">' +
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
      "</cellXfs>" +
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
      "</styleSheet>",
  ],
];

export function columnLetters(index: number): string {
  let s = "";
  let n = index + 1;
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

// XML 1.0 forbids C0 controls except TAB/LF/CR; Excel encodes them as _xHHHH_.
const XML_NEEDS_ESCAPE =
  /[&<>\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/;
const XML_ESCAPE_ALL =
  /[&<>\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g;
function xmlText(s: string): string {
  if (!XML_NEEDS_ESCAPE.test(s)) return s;
  return s.replace(XML_ESCAPE_ALL, (c) =>
    c === "&"
      ? "&amp;"
      : c === "<"
        ? "&lt;"
        : c === ">"
          ? "&gt;"
          : "_x" +
            c.charCodeAt(0).toString(16).toUpperCase().padStart(4, "0") +
            "_"
  );
}

const NUMBER_RE = /^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/;

export interface XlsxColumn {
  name: string;
  type: XlsxColumnType;
}

export interface XlsxStreamWriter {
  readonly dataRows: number;
  readonly sheetXmlBytes: number;
  readonly zipBytes: number;
  /** values: strings in column order; "" means an empty cell. */
  writeRow(values: ReadonlyArray<string>, options?: { header?: boolean }): void;
  flush(): void;
  /** Resolves when the compressor can take more input (backpressure). */
  ready(): Promise<void>;
  /** Ends the sheet and the ZIP; resolves after the last ZIP byte was emitted. */
  finish(): Promise<void>;
}

export interface XlsxStreamWriterOptions {
  columns: ReadonlyArray<XlsxColumn>;
  /** Receives ZIP bytes in order. */
  onOutput: (chunk: Uint8Array) => void;
  compressor?: XlsxCompressor;
  level?: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9;
  maxDataRows?: number;
  batchRows?: number;
}

export function createXlsxStreamWriter({
  columns,
  onOutput,
  compressor = nativeDeflateRawAvailable() ? "native" : "fflate",
  level = 6,
  maxDataRows = EXCEL_MAX_DATA_ROWS,
  batchRows = 2000,
}: XlsxStreamWriterOptions): XlsxStreamWriter {
  const encoder = new TextEncoder();
  let zipBytes = 0;
  let zipError: Error | null = null;
  let finished = false;
  let resolveDone: () => void = () => {};
  const done = new Promise<void>((resolve) => (resolveDone = resolve));
  const zip = new Zip((error, chunk, final) => {
    if (error) {
      zipError = error;
      resolveDone();
      return;
    }
    zipBytes += chunk.length;
    onOutput(chunk);
    if (final) resolveDone();
  });
  const mtime = new Date();
  for (const [name, content] of STATIC_PARTS) {
    const part = new ZipDeflate(name, { level });
    part.mtime = mtime;
    zip.add(part);
    part.push(encoder.encode(content), true);
  }
  const sheet =
    compressor === "native"
      ? new NativeZipDeflate("xl/worksheets/sheet1.xml")
      : new ZipDeflate("xl/worksheets/sheet1.xml", { level });
  sheet.mtime = mtime;
  zip.add(sheet);

  const letters = columns.map((_, i) => columnLetters(i));
  let sheetBytes = 0; // uncompressed sheet XML bytes
  let rowNumber = 0; // 1-based Excel row of the last written row
  let pending = "";
  let pendingRows = 0;

  const emit = (s: string, final = false) => {
    const bytes = encoder.encode(s);
    sheetBytes += bytes.length;
    if (sheetBytes > ZIP32_LIMIT || zipBytes > ZIP32_LIMIT) {
      throw new ExcelRefusedError(
        "The workbook would exceed 4 GiB. Use CSV instead.",
        "zip64"
      );
    }
    sheet.push(bytes, final);
    if (zipError) throw zipError;
  };

  const widths = columns.map((c) =>
    Math.min(60, Math.max(10, c.name.length + 2))
  );
  emit(
    XML_HEAD +
      `<worksheet xmlns="${NS_MAIN}" xmlns:r="${NS_REL}">` +
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
      '<sheetFormatPr defaultRowHeight="15"/>' +
      "<cols>" +
      widths
        .map(
          (w, i) =>
            `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`
        )
        .join("") +
      "</cols><sheetData>"
  );

  const flush = () => {
    if (pending) {
      emit(pending);
      pending = "";
      pendingRows = 0;
    }
  };

  const cellString = (ref: string, value: string, style: string) => {
    if (value.length > EXCEL_MAX_CELL_CHARS) {
      throw new ExcelRefusedError(
        `Cell ${ref} has ${value.length} characters; Excel allows at most ${EXCEL_MAX_CELL_CHARS}. Use CSV instead.`,
        "cell_too_long"
      );
    }
    const space = /^\s|\s$/.test(value) ? ' xml:space="preserve"' : "";
    return `<c r="${ref}"${style} t="inlineStr"><is><t${space}>${xmlText(value)}</t></is></c>`;
  };

  return {
    get dataRows() {
      return Math.max(0, rowNumber - 1);
    },
    get sheetXmlBytes() {
      return sheetBytes;
    },
    get zipBytes() {
      return zipBytes;
    },
    writeRow(values, { header = false } = {}) {
      if (!header && rowNumber - 1 >= maxDataRows) {
        throw new ExcelRefusedError(
          `Excel supports at most ${maxDataRows.toLocaleString("en-US").replace(/,/g, " ")} data rows and this export has more. Use CSV instead.`,
          "row_limit"
        );
      }
      rowNumber++;
      let xml = `<row r="${rowNumber}">`;
      for (let i = 0; i < columns.length; i++) {
        const value = values[i];
        if (value === undefined || value === "") continue;
        const ref = letters[i] + rowNumber;
        if (header) {
          xml += cellString(ref, value, ' s="2"');
          continue;
        }
        const type = columns[i].type;
        if (type === "number" && NUMBER_RE.test(value)) {
          xml += `<c r="${ref}"><v>${value}</v></c>`;
        } else if (type === "date") {
          const serial = excelDateSerial(value);
          xml +=
            serial === null
              ? cellString(ref, value, "")
              : `<c r="${ref}" s="1"><v>${serial}</v></c>`;
        } else {
          xml += cellString(ref, value, "");
        }
      }
      pending += xml + "</row>";
      if (++pendingRows >= batchRows) flush();
    },
    flush,
    ready() {
      return sheet instanceof NativeZipDeflate
        ? sheet.ready()
        : Promise.resolve();
    },
    async finish() {
      if (finished) throw new Error("finish called twice");
      finished = true;
      flush();
      emit("</sheetData></worksheet>", true);
      zip.end();
      await done;
      if (zipError) throw zipError;
    },
  };
}

/**
 * Types by header name, matching the historical XLSX export: the two life
 * dates as Excel dates, coordinates and statistical variables as numbers,
 * everything else (codes, postcodes, identifiers) as text.
 */
export function exportFieldTypes(
  statDefinitionCodes: ReadonlyArray<string>
): Record<string, XlsxColumnType> {
  const types: Record<string, XlsxColumnType> = {
    birth_date: "date",
    death_date: "date",
    physical_latitude: "number",
    physical_longitude: "number",
    physical_altitude: "number",
  };
  for (const code of statDefinitionCodes) types[code] = "number";
  return types;
}

export interface CsvToXlsxConverter {
  push(chunk: Uint8Array): void;
  end(): Promise<void>;
  ready(): Promise<void>;
  flush(): void;
  readonly dataRows: number;
  readonly zipBytes: number;
}

/**
 * CSV byte stream -> XLSX byte stream. The first CSV record is the header and
 * decides the columns; `fieldTypes` types them by name (default text).
 */
export function createCsvToXlsxConverter({
  fieldTypes,
  onOutput,
  compressor,
  maxDataRows,
}: {
  fieldTypes: Readonly<Record<string, XlsxColumnType>>;
  onOutput: (chunk: Uint8Array) => void;
  compressor?: XlsxCompressor;
  maxDataRows?: number;
}): CsvToXlsxConverter {
  let writer: XlsxStreamWriter | null = null;
  let width = 0;
  const parser = createCsvRecordParser((record) => {
    if (!writer) {
      width = record.length;
      writer = createXlsxStreamWriter({
        columns: record.map((name) => ({
          name,
          type: fieldTypes[name] ?? "string",
        })),
        onOutput,
        compressor,
        maxDataRows,
      });
      writer.writeRow(record, { header: true });
      return;
    }
    if (record.length !== width) {
      throw new Error(
        `CSV record ${writer.dataRows + 1} has ${record.length} fields; the header has ${width}`
      );
    }
    writer.writeRow(record);
  });
  return {
    push(chunk) {
      parser.push(chunk);
    },
    async end() {
      parser.end();
      if (!writer) throw new Error("CSV had no header");
      await writer.finish();
    },
    ready() {
      return writer ? writer.ready() : Promise.resolve();
    },
    flush() {
      writer?.flush();
    },
    get dataRows() {
      return writer ? writer.dataRows : 0;
    },
    get zipBytes() {
      return writer ? writer.zipBytes : 0;
    },
  };
}

export interface XlsxConverterOptions {
  fieldTypes: Readonly<Record<string, XlsxColumnType>>;
  compressor?: XlsxCompressor;
  maxDataRows?: number;
}

/**
 * CSV chunks in, workbook chunks out, one request at a time. The browser runs
 * it in a dedicated Worker (xlsx-export.worker.ts) so parsing, XML and
 * DEFLATE never block the page; tests run the same code in-process.
 */
export interface XlsxChunkConverter {
  /** Convert one CSV chunk; resolves with the workbook bytes it produced. */
  write(chunk: Uint8Array): Promise<Uint8Array[]>;
  /** Finish the workbook; resolves with the remaining bytes. */
  end(): Promise<Uint8Array[]>;
  /** Release resources (terminate the Worker). Safe to call twice. */
  dispose(): void;
}

/** The converter in this thread: what the Worker runs, and what tests use. */
export function createLocalXlsxConverter(
  options: XlsxConverterOptions
): XlsxChunkConverter {
  let output: Uint8Array[] = [];
  const converter = createCsvToXlsxConverter({
    ...options,
    onOutput: (chunk) => output.push(chunk),
  });
  const take = () => {
    const ready = output;
    output = [];
    return ready;
  };
  return {
    async write(chunk) {
      converter.push(chunk);
      // Hand rows to the compressor now, then wait for it (backpressure).
      converter.flush();
      await converter.ready();
      return take();
    },
    async end() {
      await converter.end();
      return take();
    },
    dispose() {
      output = [];
    },
  };
}

/**
 * An ExportSink that converts the CSV written to it into a workbook and
 * writes the workbook to `target`. close() finishes the ZIP and commits the
 * target; abort() discards it. Driven by pumpExportToSink, the XLSX export
 * therefore has the CSV export's guarantees: the file is committed only when
 * the CSV records received equal the announced total, and any failure,
 * including an Excel refusal mid-stream, aborts the target.
 */
export function createXlsxSink(
  target: ExportSink,
  converter: XlsxChunkConverter
): ExportSink & { readonly xlsxBytes: number } {
  let xlsxBytes = 0;
  const forward = async (chunks: Uint8Array[]) => {
    for (const chunk of chunks) {
      xlsxBytes += chunk.byteLength;
      await target.write(chunk);
    }
  };
  return {
    kind: target.kind,
    get xlsxBytes() {
      return xlsxBytes;
    },
    async write(chunk) {
      await forward(await converter.write(chunk));
    },
    async close() {
      try {
        await forward(await converter.end());
      } finally {
        converter.dispose();
      }
      await target.close();
    },
    async abort(reason) {
      converter.dispose();
      await target.abort(reason);
    },
  };
}
