import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
import { to as copyTo } from 'pg-copy-streams';
import { PassThrough } from 'stream';
import ExcelJS from '@protobi/exceljs';
import { getDbHostPort } from "@/lib/db-listener";
import type { DefinitionSnapshot } from "@/atoms/import";
import { fetchReferenceData, writeReferenceSheets, getColumnValidationMap } from '@/lib/excel-reference-sheets';

const getDbConfig = () => {
  const { dbHost, dbPort, dbName } = getDbHostPort();
  return {
    host: dbHost,
    port: dbPort,
    database: dbName,
    user: "authenticator",
    password: process.env.POSTGRES_AUTHENTICATOR_PASSWORD,
  };
};

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const slug = searchParams.get("slug");
    const filter = searchParams.get("filter");

    if (!slug) {
      return NextResponse.json({ message: "Missing slug parameter" }, { status: 400 });
    }
    if (!filter || !["error", "warning", "ok", "full"].includes(filter)) {
      return NextResponse.json({ message: "filter must be 'error', 'warning', 'ok', or 'full'" }, { status: 400 });
    }

    const format = searchParams.get("format") || "csv";
    if (!["csv", "xlsx"].includes(format)) {
      return NextResponse.json({ message: "format must be 'csv' or 'xlsx'" }, { status: 400 });
    }

    const accessToken = request.cookies.get('statbus')?.value;
    if (!accessToken) {
      return NextResponse.json({ message: "Authentication required" }, { status: 401 });
    }

    // Fetch job details via PostgREST (respects RLS)
    const client = await getServerRestClient();
    const { data: job, error: jobError } = await client
      .from("import_job")
      .select("data_table_name, definition_snapshot, slug")
      .eq("slug", slug)
      .single();

    if (jobError || !job) {
      return NextResponse.json(
        { message: `Import job not found: ${jobError?.message || "No job with that slug"}` },
        { status: 404 }
      );
    }

    const snapshot = job.definition_snapshot as DefinitionSnapshot | null;
    if (!snapshot?.import_mapping_list || !snapshot?.import_source_column_list) {
      return NextResponse.json(
        { message: "Job definition_snapshot is missing mapping information" },
        { status: 400 }
      );
    }

    // Build a priority lookup from source columns
    const priorityMap = new Map<string, number>();
    for (const sc of snapshot.import_source_column_list) {
      priorityMap.set(sc.column_name, sc.priority);
    }

    // Build SELECT column list: source_input columns only, aliased back to source names
    const columnEntries: Array<{ dataCol: string; sourceCol: string; priority: number }> = [];
    for (const mapping of snapshot.import_mapping_list) {
      if (!mapping.source_column) continue; // skip source_expression-only mappings
      if (mapping.target_data_column.purpose !== "source_input") continue;
      const priority = priorityMap.get(mapping.source_column.column_name) ?? 999;
      columnEntries.push({
        dataCol: mapping.target_data_column.column_name,
        sourceCol: mapping.source_column.column_name,
        priority,
      });
    }

    // Sort by source column priority
    columnEntries.sort((a, b) => a.priority - b.priority);

    if (columnEntries.length === 0) {
      return NextResponse.json(
        { message: "No source_input columns found in definition_snapshot" },
        { status: 400 }
      );
    }

    // Build SQL column expressions with aliases
    const sourceColumns = columnEntries
      .map(e => `${quoteIdent(e.dataCol)} AS ${quoteIdent(e.sourceCol)}`)
      .join(", ");

    // row_id and errors/warnings are added so users can identify problem rows and
    // see what went wrong. This enables a fix-and-reupload workflow: download errors,
    // correct the data in Excel/CSV, re-upload the same file.
    // On re-upload these columns are stripped automatically:
    //   - Server-side: api/import/upload/route.ts (for CSV and curl uploads)
    //   - Client-side: lib/excel-to-csv.ts (for browser Excel uploads)
    // The "error" filter includes both errors AND warnings — all problems in one file.
    const errorColumn = filter === "error"
      ? `errors::text AS "errors", warnings::text AS "warnings"`
      : filter === "warning"
      ? `warnings::text AS "warnings"`
      : null;

    // Build WHERE clause
    const whereClause = filter === "error"
      ? `WHERE state = 'error' OR (warnings IS NOT NULL AND warnings != '{}'::jsonb)`
      : filter === "warning"
      ? `WHERE warnings IS NOT NULL AND warnings != '{}'::jsonb`
      : filter === "ok"
      ? `WHERE state != 'error' AND (errors IS NULL OR errors = '{}'::jsonb) AND (warnings IS NULL OR warnings = '{}'::jsonb)`
      : ''; // full — no filter

    const dataTable = job.data_table_name;
    const selectColumns = errorColumn
      ? `row_id, ${errorColumn}, ${sourceColumns}`
      : `row_id, ${sourceColumns}`;
    const selectBody = `SELECT ${selectColumns} FROM ${quoteIdent(dataTable)} ${whereClause} ORDER BY row_id`;

    // Connect to PG and switch to user's role
    const dbConfig = getDbConfig();
    const pool = new Pool(dbConfig);
    const pgClient = await pool.connect();

    try {
      await pgClient.query('SELECT auth.jwt_switch_role($1)', [accessToken]);
    } catch (error) {
      pgClient.release();
      await pool.end();
      throw error;
    }

    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;
      pgClient.release();
      pool.end();
    };

    const filterSuffix = filter === "full" ? "-full"
      : filter === "ok" ? "-ok-rows"
      : filter === "error" ? "-errors"
      : "-warnings";

    if (format === "xlsx") {
      const numericOids = new Set([20, 21, 23, 700, 701, 1700]);
      const dateOids = new Set([1082]);
      const timestampOids = new Set([1114, 1184]);
      const boolOid = 16;
      const CURSOR_BATCH_SIZE = 5000;

      // Check row count — Excel has a hard limit of 1,048,576 rows per sheet
      const countResult = await pgClient.query(
        `SELECT COUNT(*)::int AS total FROM ${quoteIdent(dataTable)} ${whereClause}`
      );
      const totalRows: number = countResult.rows[0].total;
      if (totalRows > 1_048_576) {
        cleanup();
        return NextResponse.json(
          { message: `Dataset has ${totalRows.toLocaleString()} rows, exceeding Excel's ~1M row limit. Please download as CSV.` },
          { status: 400 }
        );
      }

      // Prepare reference data and validation info before streaming
      const prefixColumnCount = errorColumn ? 2 : 1;
      const standardizedColumnNames = columnEntries.map(e => e.dataCol.replace(/_raw$/, ''));

      const settingsResult = await client.from("settings").select("region_version_id").single();
      const regionVersionId = settingsResult.data?.region_version_id;
      const refData = await fetchReferenceData(standardizedColumnNames, client, regionVersionId);

      // Build validation map filtered by refs that actually have data
      const validationMap = getColumnValidationMap(standardizedColumnNames, refData, prefixColumnCount);

      // Use SQL cursor to fetch rows in batches — never loads all rows into memory
      await pgClient.query('BEGIN');
      await pgClient.query(`DECLARE download_cursor CURSOR FOR ${selectBody}`);

      // First batch to get field metadata
      const firstBatch = await pgClient.query(`FETCH ${CURSOR_BATCH_SIZE} FROM download_cursor`);
      const fields = firstBatch.fields;
      const fieldNames = fields.map(f => f.name);

      // Helper to convert a PG row to Excel values
      const convertRow = (row: Record<string, unknown>) =>
        fields.map((field) => {
          const val = row[field.name];
          if (val === null || val === undefined) return null;
          const oid = field.dataTypeID;
          if (numericOids.has(oid)) return Number(val);
          if (dateOids.has(oid) || timestampOids.has(oid)) return new Date(val as string);
          if (oid === boolOid) return Boolean(val);
          return val;
        });

      // Create streaming workbook writer — PassThrough connects writer to response
      const passThrough = new PassThrough();
      let aborted = false;

      // Set up response stream FIRST, before writing any data.
      // This ensures backpressure flows correctly from client → PassThrough → WorkbookWriter.
      const webStream = new ReadableStream({
        start(controller) {
          passThrough.on('data', (chunk: Buffer) => controller.enqueue(chunk));
          passThrough.on('end', () => { controller.close(); cleanup(); });
          passThrough.on('error', (err) => { controller.error(err); cleanup(); });
        },
        cancel() {
          aborted = true;
          passThrough.destroy();
          pgClient.query('CLOSE download_cursor').catch(() => {});
          pgClient.query('ROLLBACK').catch(() => {});
          cleanup();
        },
      });

      // Write data asynchronously — the ReadableStream consumer drives backpressure
      const writeExcel = async () => {
        try {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const workbook = new (ExcelJS as any).stream.xlsx.WorkbookWriter({ stream: passThrough });
          const dataSheet = workbook.addWorksheet("Data");

          // Set column formats BEFORE committing the header row — WorkbookWriter
          // serializes column metadata on the first row.commit() call.
          for (let colIdx = 0; colIdx < fields.length; colIdx++) {
            const oid = fields[colIdx].dataTypeID;
            if (dateOids.has(oid)) {
              dataSheet.getColumn(colIdx + 1).numFmt = 'yyyy-mm-dd';
            } else if (timestampOids.has(oid)) {
              dataSheet.getColumn(colIdx + 1).numFmt = 'yyyy-mm-dd hh:mm:ss';
            }
          }

          const headerRow = dataSheet.addRow(fieldNames);
          headerRow.commit();

          // Stream data rows from cursor in batches
          let batch = firstBatch;
          while (batch.rows.length > 0 && !aborted) {
            for (const pgRow of batch.rows) {
              const excelRow = dataSheet.addRow(convertRow(pgRow));
              for (const [colIdx, validation] of validationMap) {
                excelRow.getCell(colIdx).dataValidation = validation;
              }
              excelRow.commit();
            }
            await new Promise(resolve => setImmediate(resolve));
            if (aborted) break;
            batch = await pgClient.query(`FETCH ${CURSOR_BATCH_SIZE} FROM download_cursor`);
          }

          await dataSheet.commit();
          writeReferenceSheets(workbook, refData, true);
          await workbook.commit();
          await pgClient.query('CLOSE download_cursor');
          await pgClient.query('COMMIT');
        } catch (err) {
          // Rollback transaction on any error during streaming
          await pgClient.query('ROLLBACK').catch(() => {});
          if (!aborted) {
            passThrough.destroy(err instanceof Error ? err : new Error(String(err)));
          }
          cleanup();
        }
      };

      // Fire and forget — the async write drives data into the PassThrough
      // which is consumed by the ReadableStream returned in the Response
      writeExcel();

      const filename = `${slug}${filterSuffix}.xlsx`;
      return new Response(webStream, {
        headers: {
          "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          "Content-Disposition": `attachment; filename="${filename}"`,
        },
      });
    }

    // CSV path: stream via COPY
    const copyQuery = `COPY (${selectBody}) TO STDOUT WITH (FORMAT CSV, HEADER)`;
    const copyStream = pgClient.query(copyTo(copyQuery));

    const webStream = new ReadableStream({
      start(controller) {
        copyStream.on('data', (chunk: Buffer) => controller.enqueue(chunk));
        copyStream.on('end', () => { controller.close(); cleanup(); });
        copyStream.on('error', (err) => { controller.error(err); cleanup(); });
      },
      cancel() { copyStream.destroy(); cleanup(); },
    });

    const filename = `${slug}${filterSuffix}.csv`;
    return new Response(webStream, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  } catch (error) {
    console.error("Error in download handler:", error);
    return NextResponse.json(
      { message: `Server error: ${error instanceof Error ? error.message : String(error)}` },
      { status: 500 }
    );
  }
}

function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}
