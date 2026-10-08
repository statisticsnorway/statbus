/**
 * The export stream's guarantees, tested without a database (STATBUS-421):
 * a fake pg Client answers the transaction/auth/count statements and a fake
 * COPY stream supplies the CSV bytes plus COPY's own row count.
 */
import { Readable } from "stream";

type FakeCopy = Readable & { rowCount: number; sql: string };

const fake = {
  queries: [] as string[],
  countTotal: 3,
  copyChunks: [] as string[],
  copyRowCount: 3,
  failSwitchRole: null as string | null,
  failCopyAfterChunks: null as number | null,
  ended: false,
};

jest.mock("@/lib/db-listener", () => ({
  getDbHostPort: () => ({ dbHost: "h", dbPort: 1, dbName: "d" }),
}));

jest.mock("pg-copy-streams", () => ({
  to: (sql: string) => {
    let sent = 0;
    const stream = new Readable({
      read() {
        if (
          fake.failCopyAfterChunks != null &&
          sent === fake.failCopyAfterChunks
        ) {
          this.destroy(
            new Error("terminating connection due to administrator command")
          );
          return;
        }
        if (sent < fake.copyChunks.length) {
          this.push(Buffer.from(fake.copyChunks[sent++]));
        } else {
          (stream as FakeCopy).rowCount = fake.copyRowCount;
          this.push(null);
        }
      },
    }) as FakeCopy;
    stream.sql = sql;
    stream.rowCount = 0;
    return stream;
  },
}));

jest.mock("pg", () => ({
  Client: jest.fn().mockImplementation(() => ({
    connect: async () => {},
    on: () => {},
    end: async () => {
      fake.ended = true;
    },
    query: (q: unknown, values?: unknown[]) => {
      if (typeof q !== "string") return q; // the COPY stream
      fake.queries.push(q);
      if (q.includes("auth.jwt_switch_role") && fake.failSwitchRole) {
        return Promise.reject(new Error(fake.failSwitchRole));
      }
      if (q.startsWith("SELECT count(*)")) {
        return Promise.resolve({ rows: [{ total: String(fake.countTotal) }] });
      }
      void values;
      return Promise.resolve({ rows: [] });
    },
  })),
}));

import { openExportStream } from "./export-copy-stream";

const columnConfig = { externalIdentCodes: [], statCodes: [] };
const CSV = ["name\n", "a\n", "b\n", "c\n"];

beforeEach(() => {
  fake.queries = [];
  fake.countTotal = 3;
  fake.copyChunks = [...CSV];
  fake.copyRowCount = 3;
  fake.failSwitchRole = null;
  fake.failCopyAfterChunks = null;
  fake.ended = false;
});

async function drain(stream: ReadableStream<Uint8Array>): Promise<string> {
  return new Response(stream).text();
}

describe("openExportStream", () => {
  it("runs as the user's role inside one read-only snapshot, count before COPY", async () => {
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams({ unit_type: "in.(legal_unit)" }),
      columnConfig,
    });
    expect(result.kind).toBe("stream");
    expect(fake.queries[0]).toBe(
      "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY"
    );
    expect(fake.queries[1]).toBe("SELECT auth.jwt_switch_role($1)");
    expect(
      fake.queries.findIndex((q) => q.startsWith("SELECT count(*)"))
    ).toBeGreaterThan(1);
  });

  it("streams the CSV and ends cleanly when COPY's row count equals the announced count", async () => {
    const onSuccess = jest.fn();
    const onFailure = jest.fn();
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams(),
      columnConfig,
      onSuccess,
      onFailure,
    });
    if (result.kind !== "stream") throw new Error("expected a stream");
    expect(result.totalRows).toBe(3);
    await expect(drain(result.stream)).resolves.toBe(CSV.join(""));
    expect(onFailure).not.toHaveBeenCalled();
    expect(onSuccess).toHaveBeenCalledWith(
      expect.objectContaining({ rowsSent: 3, expectedRows: 3 })
    );
    expect(fake.queries).toContain("COMMIT");
  });

  it("errors the stream (never a clean end) when COPY's row count differs from the announced count", async () => {
    fake.copyRowCount = 2;
    const onFailure = jest.fn();
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams(),
      columnConfig,
      onFailure,
    });
    if (result.kind !== "stream") throw new Error("expected a stream");
    await expect(drain(result.stream)).rejects.toThrow(/row count mismatch/);
    expect(onFailure).toHaveBeenCalledWith(
      expect.objectContaining({ expectedRows: 3, rowsSent: 3 })
    );
    expect(fake.queries).not.toContain("COMMIT");
  });

  it("errors the stream when the streamed records differ from the announced count", async () => {
    fake.copyChunks = ["name\n", "a\n", "b\n"]; // COPY claims 3, only 2 arrive
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams(),
      columnConfig,
    });
    if (result.kind !== "stream") throw new Error("expected a stream");
    await expect(drain(result.stream)).rejects.toThrow(/row count mismatch/);
  });

  it("reports a mid-stream database failure with rows and bytes sent", async () => {
    fake.failCopyAfterChunks = 2;
    const onFailure = jest.fn();
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams(),
      columnConfig,
      onFailure,
    });
    if (result.kind !== "stream") throw new Error("expected a stream");
    await expect(drain(result.stream)).rejects.toThrow(/administrator command/);
    expect(onFailure).toHaveBeenCalledWith(
      expect.objectContaining({
        rowsSent: 1,
        bytesSent: "name\na\n".length,
        expectedRows: 3,
      })
    );
    expect(fake.ended).toBe(true);
  });

  it("refuses before streaming when the count exceeds maxRows", async () => {
    fake.countTotal = 1_048_576;
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams(),
      columnConfig,
      maxRows: 1_048_575,
    });
    expect(result).toEqual({
      kind: "too-many-rows",
      totalRows: 1_048_576,
      maxRows: 1_048_575,
    });
    expect(fake.queries.some((q) => q.startsWith("COPY"))).toBe(false);
    expect(fake.ended).toBe(true);
  });

  it("streams at exactly maxRows", async () => {
    fake.countTotal = 3;
    const result = await openExportStream({
      accessToken: "tok",
      params: new URLSearchParams(),
      columnConfig,
      maxRows: 3,
    });
    expect(result.kind).toBe("stream");
  });

  it("propagates an authentication failure before any byte and closes the connection", async () => {
    fake.failSwitchRole = "Token has expired";
    await expect(
      openExportStream({
        accessToken: "tok",
        params: new URLSearchParams(),
        columnConfig,
      })
    ).rejects.toThrow("Token has expired");
    expect(fake.queries.some((q) => q.startsWith("SELECT count(*)"))).toBe(
      false
    );
    expect(fake.ended).toBe(true);
  });
});
