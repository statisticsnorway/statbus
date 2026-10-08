import {
  createMemorySink,
  createWritableSink,
  ExportCancelledError,
  ExportIncompleteError,
  ExportStreamError,
  excelRowLimitError,
  parseAnnouncedTotal,
  pickSaveFile,
  pumpExportToSink,
  type ExportSink,
} from "./export-download";

const encoder = new TextEncoder();

function streamOf(
  parts: string[],
  failAfter?: number
): ReadableStream<Uint8Array> {
  let index = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      if (failAfter != null && index === failAfter) {
        controller.error(new TypeError("network error"));
        return;
      }
      if (index < parts.length)
        controller.enqueue(encoder.encode(parts[index++]));
      else controller.close();
    },
  });
}

function recordingSink() {
  const log: string[] = [];
  let written = "";
  const decoder = new TextDecoder();
  const sink: ExportSink = {
    kind: "memory",
    async write(chunk) {
      written += decoder.decode(chunk, { stream: true });
    },
    async close() {
      log.push("close");
    },
    async abort() {
      log.push("abort");
    },
  };
  return { sink, log, written: () => written };
}

describe("pumpExportToSink", () => {
  it("writes every byte and commits when the records equal the announced total", async () => {
    const { sink, log, written } = recordingSink();
    const progress: number[] = [];
    const result = await pumpExportToSink(
      streamOf(["name\n", '"a\nb"\n', "c\n"]),
      sink,
      2,
      (p) => progress.push(p.rowsReceived)
    );
    // "name\n" (5) + '"a\nb"\n' (6) + "c\n" (2) = 13 bytes.
    expect(result).toEqual({
      rowsReceived: 2,
      bytesReceived: 13,
      expectedRows: 2,
    });
    expect(written()).toBe('name\n"a\nb"\nc\n');
    expect(log).toEqual(["close"]);
    expect(progress).toEqual([0, 1, 2]);
  });

  it("never commits a short export: aborts and reports received vs expected", async () => {
    const { sink, log } = recordingSink();
    const pumped = pumpExportToSink(streamOf(["name\n", "a\n"]), sink, 3);
    await expect(pumped).rejects.toBeInstanceOf(ExportIncompleteError);
    await expect(pumped).rejects.toThrow(
      "received 1 of 3 rows. The file was not saved"
    );
    expect(log).toEqual(["abort"]);
  });

  it("never commits a long export either", async () => {
    const { sink, log } = recordingSink();
    await expect(
      pumpExportToSink(streamOf(["name\n", "a\n", "b\n"]), sink, 1)
    ).rejects.toBeInstanceOf(ExportIncompleteError);
    expect(log).toEqual(["abort"]);
  });

  it("aborts on a mid-stream network failure, with the rows that had arrived", async () => {
    const { sink, log } = recordingSink();
    const pumped = pumpExportToSink(
      streamOf(["name\n", "a\n", "b\n", "c\n"], 2),
      sink,
      3
    );
    await expect(pumped).rejects.toBeInstanceOf(ExportStreamError);
    await expect(pumped).rejects.toMatchObject({
      rowsReceived: 1,
      expectedRows: 3,
    });
    await expect(pumped).rejects.toThrow(
      /interrupted after 1 of 3 rows: network error/
    );
    expect(log).toEqual(["abort"]);
  });

  it("aborts when the disk write fails", async () => {
    const { sink, log } = recordingSink();
    sink.write = async () => {
      throw new Error("QuotaExceededError");
    };
    await expect(
      pumpExportToSink(streamOf(["name\n", "a\n"]), sink, 1)
    ).rejects.toThrow(/QuotaExceededError/);
    expect(log).toEqual(["abort"]);
  });

  it("accepts an empty export with only a header", async () => {
    const { sink, log } = recordingSink();
    await expect(
      pumpExportToSink(streamOf(["name\n"]), sink, 0)
    ).resolves.toMatchObject({
      rowsReceived: 0,
    });
    expect(log).toEqual(["close"]);
  });
});

describe("excelRowLimitError", () => {
  it("accepts exactly the sheet's data-row capacity", () => {
    expect(excelRowLimitError(1_048_575)).toBeNull();
    expect(excelRowLimitError(0)).toBeNull();
    expect(excelRowLimitError(null)).toBeNull(); // no total yet: re-checked on arrival
  });

  it("refuses one row more, and the Norway export, pointing at CSV", () => {
    expect(excelRowLimitError(1_048_576)).toBe(
      "Excel supports at most 1 048 575 data rows; this export has 1 048 576. Use CSV instead."
    );
    expect(excelRowLimitError(1_976_463)).toMatch(
      /this export has 1 976 463\. Use CSV instead\.$/
    );
  });
});

describe("parseAnnouncedTotal", () => {
  it("reads the exact total the route announces", () => {
    expect(parseAnnouncedTotal("1976463")).toBe(1976463);
    expect(parseAnnouncedTotal("0")).toBe(0);
  });

  it("refuses a missing or empty header instead of reading it as 0 rows", () => {
    expect(parseAnnouncedTotal(null)).toBeNull();
    expect(parseAnnouncedTotal("")).toBeNull();
    expect(parseAnnouncedTotal(" ")).toBeNull();
  });

  it("refuses anything that is not a plain non-negative integer", () => {
    for (const bad of ["-1", "1.5", "1e3", "0x10", "12abc", "NaN"]) {
      expect(parseAnnouncedTotal(bad)).toBeNull();
    }
  });
});

describe("pickSaveFile", () => {
  const original = (globalThis as { window?: unknown }).window;
  afterEach(() => {
    (globalThis as { window?: unknown }).window = original;
  });

  it("suggests the export's filename and restricts the type to its extension", async () => {
    const calls: unknown[] = [];
    const handle = {} as FileSystemFileHandle;
    (globalThis as { window?: unknown }).window = {
      showSaveFilePicker: async (options: unknown) => {
        calls.push(options);
        return handle;
      },
    };
    await expect(
      pickSaveFile("establishments.csv", "CSV file", "text/csv", ".csv")
    ).resolves.toBe(handle);
    expect(calls).toEqual([
      {
        suggestedName: "establishments.csv",
        types: [{ description: "CSV file", accept: { "text/csv": [".csv"] } }],
      },
    ]);
  });

  it("turns a dismissed dialog into a cancellation, not an error", async () => {
    (globalThis as { window?: unknown }).window = {
      showSaveFilePicker: async () => {
        throw new DOMException("The user aborted a request.", "AbortError");
      },
    };
    await expect(
      pickSaveFile("x.csv", "CSV file", "text/csv", ".csv")
    ).rejects.toBeInstanceOf(ExportCancelledError);
  });

  it("lets any other picker failure through as an error", async () => {
    (globalThis as { window?: unknown }).window = {
      showSaveFilePicker: async () => {
        throw new DOMException("Not allowed", "SecurityError");
      },
    };
    await expect(
      pickSaveFile("x.csv", "CSV file", "text/csv", ".csv")
    ).rejects.toMatchObject({ name: "SecurityError" });
  });
});

describe("createMemorySink", () => {
  const originalDocument = (globalThis as { document?: unknown }).document;
  afterEach(() => {
    (globalThis as { document?: unknown }).document = originalDocument;
    jest.restoreAllMocks();
  });

  function fakeDocument() {
    // saveBlob revokes the object URL after 60 s; keep that timer out of
    // the test process so jest exits promptly.
    jest
      .spyOn(globalThis, "setTimeout")
      .mockImplementation((() => 0) as unknown as typeof setTimeout);
    const anchors: Array<{ href: string; download: string; clicks: number }> =
      [];
    (globalThis as { document?: unknown }).document = {
      createElement: () => {
        const anchor = {
          href: "",
          download: "",
          clicks: 0,
          click() {
            this.clicks++;
          },
        };
        anchors.push(anchor);
        return anchor;
      },
      body: { appendChild: () => {}, removeChild: () => {} },
    };
    return anchors;
  }

  it("downloads every chunk under the export's filename and type on close", async () => {
    const anchors = fakeDocument();
    const blobs: Blob[] = [];
    jest.spyOn(URL, "createObjectURL").mockImplementation((blob) => {
      blobs.push(blob as Blob);
      return "blob:test";
    });
    const sink = createMemorySink(
      "unit_7_history.csv",
      "text/csv;charset=utf-8"
    );
    await sink.write(encoder.encode("name\n"));
    await sink.write(encoder.encode("a\n"));
    expect(anchors).toHaveLength(0); // nothing is saved before close
    await sink.close();
    expect(anchors).toEqual([
      expect.objectContaining({
        href: "blob:test",
        download: "unit_7_history.csv",
        clicks: 1,
      }),
    ]);
    expect(blobs[0].type).toBe("text/csv;charset=utf-8");
    expect(await blobs[0].text()).toBe("name\na\n");
  });

  it("saves nothing when aborted", async () => {
    const anchors = fakeDocument();
    const sink = createMemorySink("x.csv", "text/csv");
    await sink.write(encoder.encode("name\n"));
    await sink.abort();
    expect(anchors).toHaveLength(0);
  });
});

describe("createWritableSink", () => {
  it("coalesces chunks into large writes and flushes the rest on close", async () => {
    const writes: number[] = [];
    const calls: string[] = [];
    const sink = createWritableSink(
      {
        write: async (data) => {
          writes.push(data.byteLength);
        },
        close: async () => {
          calls.push("close");
        },
        abort: async () => {
          calls.push("abort");
        },
      },
      "file-picker"
    );
    const chunk = new Uint8Array(400 * 1024);
    for (let i = 0; i < 5; i++) await sink.write(chunk);
    await sink.close();
    expect(writes).toEqual([1200 * 1024, 800 * 1024]);
    expect(calls).toEqual(["close"]);
  });

  it("abort discards buffered bytes and aborts the file", async () => {
    const writes: number[] = [];
    const calls: string[] = [];
    const sink = createWritableSink(
      {
        write: async (data) => {
          writes.push(data.byteLength);
        },
        close: async () => {
          calls.push("close");
        },
        abort: async () => {
          calls.push("abort");
        },
      },
      "opfs"
    );
    await sink.write(new Uint8Array(10));
    await sink.abort();
    expect(writes).toEqual([]);
    expect(calls).toEqual(["abort"]);
  });
});
