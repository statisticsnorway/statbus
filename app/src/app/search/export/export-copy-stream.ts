import { Client } from "pg";
import { to as copyTo } from "pg-copy-streams";
import { getDbHostPort } from "@/lib/db-listener";
import { composeExportSql, type ExportColumnConfig } from "./export-sql";
import { createCsvRowCounter } from "./csv-row-counter";

/**
 * The server half of the statistical-unit export (STATBUS-421 Phase 2).
 *
 * One dedicated connection as `authenticator`, one READ ONLY REPEATABLE READ
 * transaction, `auth.jwt_switch_role(<user's access token>)` so the export
 * runs as the user's own role under RLS, then:
 *   1. the enabled identifier/statistic codes (same snapshot),
 *   2. count(*) over the filter (same snapshot) -> the announced total,
 *   3. COPY (<export select>) TO STDOUT WITH (FORMAT CSV, HEADER).
 * Because 2 and 3 share one snapshot, the COPY returns exactly the announced
 * number of rows; the stream verifies that against COPY's own row count and
 * fails (never closes cleanly) on any difference.
 *
 * Memory is constant: COPY streams, and the web stream below pulls from the
 * COPY stream only when the HTTP consumer asks for more (backpressure all the
 * way from the browser's reader to PostgreSQL's socket).
 */

/**
 * Export-specific statement timeout. The `authenticated` role's 120 s is a
 * login-time default that SET ROLE does not apply; an export that streams
 * 400+ MB to a slow client legitimately runs longer than an API call, and the
 * client's backpressure keeps the statement open while it writes to disk.
 */
export const EXPORT_STATEMENT_TIMEOUT = "30min";

export interface ExportStreamFailure {
  error: string;
  rowsSent: number;
  bytesSent: number;
  expectedRows: number;
  elapsedMs: number;
}

export interface ExportStreamSuccess {
  rowsSent: number;
  bytesSent: number;
  expectedRows: number;
  elapsedMs: number;
}

export interface OpenExportOptions {
  accessToken: string;
  params: URLSearchParams;
  /**
   * Column codes; when omitted they are read from the enabled
   * external_ident_type / stat_definition views in the export's snapshot.
   */
  columnConfig?: ExportColumnConfig;
  /** Refuse (before streaming) when the total exceeds this many rows. */
  maxRows?: number | null;
  onFailure?: (failure: ExportStreamFailure) => void;
  onSuccess?: (success: ExportStreamSuccess) => void;
  /** Override the connection (tests and measurement harnesses). */
  connectionConfig?: ConstructorParameters<typeof Client>[0];
}

export type OpenExportResult =
  | {
      kind: "stream";
      stream: ReadableStream<Uint8Array>;
      totalRows: number;
      fieldNames: string[];
      /** Abort the export (client went away): ends the connection. */
      abort: () => void;
    }
  | { kind: "too-many-rows"; totalRows: number; maxRows: number };

function defaultConnectionConfig() {
  const { dbHost, dbPort, dbName } = getDbHostPort();
  return {
    host: dbHost,
    port: dbPort,
    database: dbName,
    user: "authenticator",
    password: process.env.POSTGRES_AUTHENTICATOR_PASSWORD,
    application_name: "statbus-export",
  };
}

async function readColumnConfig(client: Client): Promise<ExportColumnConfig> {
  const externalIdents = await client.query<{ code: string }>(
    "SELECT code FROM public.external_ident_type_enabled ORDER BY priority, code"
  );
  const stats = await client.query<{ code: string }>(
    "SELECT code FROM public.stat_definition_enabled ORDER BY priority, code"
  );
  return {
    externalIdentCodes: externalIdents.rows.map((row) => row.code),
    statCodes: stats.rows.map((row) => row.code),
  };
}

/**
 * Open the export: authenticate, count, and return a web stream of the CSV.
 * Throws (before any byte is streamed) on authentication or query errors,
 * and ExportQueryError on an unsupported filter.
 */
export async function openExportStream(
  options: OpenExportOptions
): Promise<OpenExportResult> {
  const startTime = Date.now();
  const client = new Client(
    options.connectionConfig ?? defaultConnectionConfig()
  );
  await client.connect();

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    client.end().catch(() => {});
  };
  // A broken connection must not crash the process; the stream reports it.
  client.on("error", () => close());

  try {
    await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
    await client.query("SELECT auth.jwt_switch_role($1)", [
      options.accessToken,
    ]);
    // Literals in the composed SQL rely on standard_conforming_strings, and
    // the CSV's date format must not depend on the database's DateStyle.
    await client.query(
      `SELECT set_config('standard_conforming_strings', 'on', true),
              set_config('DateStyle', 'ISO, YMD', true),
              set_config('statement_timeout', $1, true)`,
      [EXPORT_STATEMENT_TIMEOUT]
    );

    const columnConfig =
      options.columnConfig ?? (await readColumnConfig(client));
    const { selectSql, countSql, fieldNames } = composeExportSql(
      options.params,
      columnConfig
    );

    const countResult = await client.query<{ total: string }>(countSql);
    const totalRows = Number(countResult.rows[0].total);

    if (options.maxRows != null && totalRows > options.maxRows) {
      await client.query("ROLLBACK").catch(() => {});
      close();
      return { kind: "too-many-rows", totalRows, maxRows: options.maxRows };
    }

    const copyStream = client.query(
      copyTo(`COPY (${selectSql}) TO STDOUT WITH (FORMAT CSV, HEADER)`)
    );
    const iterator = copyStream[
      Symbol.asyncIterator
    ]() as AsyncIterator<Buffer>;
    const counter = createCsvRowCounter();
    let bytesSent = 0;
    let finished = false;

    const fail = (error: unknown) => {
      if (finished) return;
      finished = true;
      copyStream.destroy();
      close();
      options.onFailure?.({
        error: error instanceof Error ? error.message : String(error),
        rowsSent: counter.records,
        bytesSent,
        expectedRows: totalRows,
        elapsedMs: Date.now() - startTime,
      });
    };

    const stream = new ReadableStream<Uint8Array>(
      {
        async pull(controller) {
          try {
            const { done, value } = await iterator.next();
            if (!done) {
              const chunk = new Uint8Array(
                value.buffer,
                value.byteOffset,
                value.byteLength
              );
              counter.push(chunk);
              bytesSent += chunk.byteLength;
              controller.enqueue(chunk);
              return;
            }
            // COPY's command tag is the database's own row count. Together
            // with the snapshot-shared count(*) it proves completeness.
            const copied = copyStream.rowCount;
            if (copied !== totalRows || counter.records !== totalRows) {
              throw new Error(
                `Export row count mismatch: COPY sent ${copied} rows (${counter.records} counted in the stream), the count announced ${totalRows}`
              );
            }
            await client.query("COMMIT");
            finished = true;
            close();
            controller.close();
            options.onSuccess?.({
              rowsSent: counter.records,
              bytesSent,
              expectedRows: totalRows,
              elapsedMs: Date.now() - startTime,
            });
          } catch (error) {
            fail(error);
            controller.error(error);
          }
        },
        cancel(reason) {
          fail(reason ?? new Error("Export cancelled by the client"));
        },
      },
      // Pull one COPY chunk (about 64 KiB) at a time.
      { highWaterMark: 1 }
    );

    return {
      kind: "stream",
      stream,
      totalRows,
      fieldNames,
      abort: () => fail(new Error("Export aborted: the client disconnected")),
    };
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    close();
    throw error;
  }
}
