import { unzipSync, strFromU8 } from "fflate";
import {
  columnLetters,
  createCsvRecordParser,
  createCsvToXlsxConverter,
  createLocalXlsxConverter,
  createXlsxSink,
  ExcelRefusedError,
  excelDateSerial,
  exportFieldTypes,
  type XlsxCompressor,
} from "./xlsx-stream";
import {
  ExportIncompleteError,
  pumpExportToSink,
  type ExportSink,
} from "./export-download";
import {
  createWorkerXlsxConverter,
  type WorkerLike,
  type XlsxWorkerRequest,
  type XlsxWorkerResponse,
} from "./xlsx-worker-protocol";
import { EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";

const encoder = new TextEncoder();
const bytes = (s: string) => encoder.encode(s);

function concat(chunks: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.byteLength, 0));
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

/** Convert CSV text, split into `parts`, to a workbook; return its parts. */
async function convert(
  parts: string[],
  {
    compressor = "fflate",
    maxDataRows,
    fieldTypes = exportFieldTypes(["employees"]),
  }: {
    compressor?: XlsxCompressor;
    maxDataRows?: number;
    fieldTypes?: Record<string, "string" | "number" | "date">;
  } = {}
) {
  const output: Uint8Array[] = [];
  const converter = createCsvToXlsxConverter({
    fieldTypes,
    onOutput: (chunk) => output.push(chunk),
    compressor,
    maxDataRows,
  });
  for (const part of parts) {
    converter.push(bytes(part));
    await converter.ready();
  }
  await converter.end();
  // unzipSync verifies every member's CRC-32 against its contents.
  const files = unzipSync(concat(output));
  return {
    files,
    sheet: strFromU8(files["xl/worksheets/sheet1.xml"]),
    dataRows: converter.dataRows,
  };
}

/** The <row> elements of a sheet, as raw XML strings. */
function rows(sheet: string): string[] {
  return sheet.match(/<row [^>]*>.*?<\/row>/g) ?? [];
}

describe("excelDateSerial: Excel's 1900 date system", () => {
  it("is one lower before 1900-03-01, because serial 60 is the fictitious 1900-02-29", () => {
    expect(excelDateSerial("1900-01-01")).toBe(1);
    expect(excelDateSerial("1900-02-28")).toBe(59);
    expect(excelDateSerial("1900-03-01")).toBe(61);
  });

  it("matches Excel for ordinary dates", () => {
    expect(excelDateSerial("1970-01-01")).toBe(25569);
    expect(excelDateSerial("2024-01-15")).toBe(45306);
  });

  it("keeps values Excel cannot hold as a date as text (null)", () => {
    expect(excelDateSerial("1899-12-31")).toBeNull(); // before the 1900 system
    expect(excelDateSerial("2024-02-30")).toBeNull(); // not a calendar date
    expect(excelDateSerial("2024-1-5")).toBeNull();
    expect(excelDateSerial("")).toBeNull();
  });
});

describe("createCsvRecordParser", () => {
  it("handles quotes, embedded newlines, escaped quotes and chunk boundaries", () => {
    const records: string[][] = [];
    const parser = createCsvRecordParser((r) => records.push(r));
    const text = 'a,b\n"x\ny","say ""hi"""\n,\n"last","no newline"';
    // Feed one byte at a time: every state must survive a chunk boundary.
    for (const byte of bytes(text)) parser.push(new Uint8Array([byte]));
    parser.end();
    expect(records).toEqual([
      ["a", "b"],
      ["x\ny", 'say "hi"'],
      ["", ""],
      ["last", "no newline"],
    ]);
  });

  it("decodes multi-byte UTF-8 split across chunks", () => {
    const records: string[][] = [];
    const parser = createCsvRecordParser((r) => records.push(r));
    const encoded = bytes("name\nÆØÅ ærø\n");
    parser.push(encoded.subarray(0, 6)); // splits the two-byte Æ
    parser.push(encoded.subarray(6));
    parser.end();
    expect(records).toEqual([["name"], ["ÆØÅ ærø"]]);
  });

  it("refuses a stream that ends inside a quoted field", () => {
    const parser = createCsvRecordParser(() => {});
    parser.push(bytes('a\n"unterminated'));
    expect(() => parser.end()).toThrow("CSV ended inside a quoted field");
  });
});

describe("createCsvToXlsxConverter", () => {
  it("writes a valid workbook: header, typed cells, escaped text", async () => {
    const { files, sheet, dataRows } = await convert([
      "name,birth_date,employees,physical_postcode\n",
      '"A & B <AS>",1900-01-01,12,0150\n',
      "C,1850-06-01,,\n",
    ]);
    expect(Object.keys(files).sort()).toEqual([
      "[Content_Types].xml",
      "_rels/.rels",
      "docProps/app.xml",
      "xl/_rels/workbook.xml.rels",
      "xl/styles.xml",
      "xl/workbook.xml",
      "xl/worksheets/sheet1.xml",
    ]);
    expect(dataRows).toBe(2);
    const [header, first, second] = rows(sheet);
    expect(header).toContain('<c r="A1" s="2" t="inlineStr"><is><t>name</t>');
    // Text is escaped, the sentinel date is serial 1 with the date style,
    // a statistic is a number, and a postcode keeps its leading zero.
    expect(first).toContain("<t>A &amp; B &lt;AS&gt;</t>");
    expect(first).toContain('<c r="B2" s="1"><v>1</v></c>');
    expect(first).toContain('<c r="C2"><v>12</v></c>');
    expect(first).toContain('<c r="D2" t="inlineStr"><is><t>0150</t>');
    // A pre-1900 date stays text; empty cells are omitted.
    expect(second).toContain('<c r="B3" t="inlineStr"><is><t>1850-06-01</t>');
    expect(second).not.toContain('r="C3"');
    expect(sheet.endsWith("</sheetData></worksheet>")).toBe(true);
  });

  it("produces the same sheet with the native compressor", async () => {
    const parts = ["name,employees\n", "a,1\n", "b,2\n"];
    const fflate = await convert(parts, { compressor: "fflate" });
    const native = await convert(parts, { compressor: "native" });
    expect(native.sheet).toBe(fflate.sheet);
  });

  it("accepts exactly the data-row limit", async () => {
    const { dataRows, sheet } = await convert(["n\n", "1\n", "2\n", "3\n"], {
      maxDataRows: 3,
    });
    expect(dataRows).toBe(3);
    expect(rows(sheet)).toHaveLength(4); // header + 3
  });

  it("refuses on the fly at one data row over the limit", async () => {
    const attempt = convert(["n\n", "1\n", "2\n", "3\n", "4\n"], {
      maxDataRows: 3,
    });
    await expect(attempt).rejects.toBeInstanceOf(ExcelRefusedError);
    await expect(attempt).rejects.toMatchObject({ code: "row_limit" });
    await expect(attempt).rejects.toThrow(
      "Excel supports at most 3 data rows and this export has more. Use CSV instead."
    );
  });

  it("defaults to the sheet limit, the header row excluded", () => {
    expect(EXCEL_MAX_DATA_ROWS).toBe(1_048_575);
  });

  it("refuses a cell longer than Excel allows", async () => {
    await expect(
      convert(["n\n", `${"x".repeat(32_768)}\n`])
    ).rejects.toMatchObject({ code: "cell_too_long" });
  });

  it("refuses a record whose width differs from the header", async () => {
    await expect(convert(["a,b\n", "1\n"])).rejects.toThrow(
      "CSV record 1 has 1 fields; the header has 2"
    );
  });
});

describe("columnLetters", () => {
  it("names columns like Excel", () => {
    expect([0, 25, 26, 701, 702].map(columnLetters)).toEqual([
      "A",
      "Z",
      "AA",
      "ZZ",
      "AAA",
    ]);
  });
});

function recordingTarget() {
  const log: string[] = [];
  const written: Uint8Array[] = [];
  const target: ExportSink = {
    kind: "memory",
    async write(chunk) {
      written.push(chunk.slice());
    },
    async close() {
      log.push("close");
    },
    async abort() {
      log.push("abort");
    },
  };
  return { target, log, written };
}

function streamOf(parts: string[]): ReadableStream<Uint8Array> {
  let index = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      if (index < parts.length) controller.enqueue(bytes(parts[index++]));
      else controller.close();
    },
  });
}

describe("createXlsxSink driven by pumpExportToSink", () => {
  const options = {
    fieldTypes: exportFieldTypes([]),
    compressor: "fflate" as const,
  };

  it("commits a complete workbook when the records equal the announced total", async () => {
    const { target, log, written } = recordingTarget();
    const sink = createXlsxSink(target, createLocalXlsxConverter(options));
    await pumpExportToSink(streamOf(["name\n", "a\n", "b\n"]), sink, 2);
    expect(log).toEqual(["close"]);
    const files = unzipSync(concat(written));
    expect(rows(strFromU8(files["xl/worksheets/sheet1.xml"]))).toHaveLength(3);
    expect(sink.xlsxBytes).toBe(concat(written).byteLength);
  });

  it("never commits a workbook for a short export", async () => {
    const { target, log } = recordingTarget();
    const sink = createXlsxSink(target, createLocalXlsxConverter(options));
    await expect(
      pumpExportToSink(streamOf(["name\n", "a\n"]), sink, 2)
    ).rejects.toBeInstanceOf(ExportIncompleteError);
    expect(log).toEqual(["abort"]);
  });

  it("aborts the file and shows the refusal itself when Excel's limit is crossed mid-stream", async () => {
    const { target, log } = recordingTarget();
    const sink = createXlsxSink(
      target,
      createLocalXlsxConverter({ ...options, maxDataRows: 1 })
    );
    const pumped = pumpExportToSink(
      streamOf(["name\n", "a\n", "b\n"]),
      sink,
      2
    );
    await expect(pumped).rejects.toBeInstanceOf(ExcelRefusedError);
    await expect(pumped).rejects.toThrow(/^Excel supports at most 1 data rows/);
    expect(log).toEqual(["abort"]);
  });
});

/** An in-process stand-in for the Worker, running the real worker logic. */
function fakeWorker(): WorkerLike & { terminated: boolean } {
  let converter: ReturnType<typeof createLocalXlsxConverter> | null = null;
  let queue = Promise.resolve();
  const worker: WorkerLike & { terminated: boolean } = {
    onmessage: null,
    onerror: null,
    terminated: false,
    postMessage(request: XlsxWorkerRequest) {
      queue = queue.then(async () => {
        let response: XlsxWorkerResponse;
        try {
          if (request.type === "init") {
            converter = createLocalXlsxConverter(request.options);
            response = { id: request.id, chunks: [] };
          } else {
            const chunks =
              request.type === "write"
                ? await converter!.write(request.chunk)
                : await converter!.end();
            response = { id: request.id, chunks };
          }
        } catch (error) {
          const e = error as Error & { code?: "row_limit" };
          response = {
            id: request.id,
            error: { name: e.name, message: e.message, code: e.code ?? null },
          };
        }
        worker.onmessage?.({ data: response } as MessageEvent);
      });
    },
    terminate() {
      worker.terminated = true;
    },
  };
  return worker;
}

describe("createWorkerXlsxConverter", () => {
  it("round-trips chunks and terminates the worker when the sink closes", async () => {
    const worker = fakeWorker();
    const { target, log, written } = recordingTarget();
    const sink = createXlsxSink(
      target,
      createWorkerXlsxConverter(worker, {
        fieldTypes: {},
        compressor: "fflate",
      })
    );
    await pumpExportToSink(streamOf(["name\n", "a\n"]), sink, 1);
    expect(log).toEqual(["close"]);
    expect(worker.terminated).toBe(true);
    expect(Object.keys(unzipSync(concat(written)))).toContain(
      "xl/worksheets/sheet1.xml"
    );
  });

  it("keeps an Excel refusal a refusal across the worker boundary", async () => {
    const worker = fakeWorker();
    const converter = createWorkerXlsxConverter(worker, {
      fieldTypes: {},
      compressor: "fflate",
      maxDataRows: 1,
    });
    await converter.write(bytes("name\na\n"));
    const second = converter.write(bytes("b\n"));
    await expect(second).rejects.toBeInstanceOf(ExcelRefusedError);
    await expect(second).rejects.toMatchObject({ code: "row_limit" });
  });
});
