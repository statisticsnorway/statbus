import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
import { to as copyTo } from 'pg-copy-streams';
import { PassThrough } from 'stream';
import ExcelJS from '@protobi/exceljs';
import { getDbHostPort } from "@/lib/db-listener";
import type { DefinitionSnapshot } from "@/atoms/import";
import { addReferenceSheets, applyColumnValidation } from '@/lib/excel-reference-sheets';

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

    // Diagnostic column only for error/warning filters
    const errorColumn = filter === "error"
      ? `errors::text AS "errors"`
      : filter === "warning"
      ? `warnings::text AS "warnings"`
      : null;

    // Build WHERE clause
    const whereClause = filter === "error"
      ? `WHERE state = 'error'`
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

    const cleanup = () => {
      pgClient.release();
      pool.end();
    };

    const filterSuffix = filter === "full" ? "-full"
      : filter === "ok" ? "-ok-rows"
      : filter === "error" ? "-errors"
      : "-warnings";

    if (format === "xlsx") {
      const result = await pgClient.query(selectBody);
      const fields = result.fields.map(f => f.name);

      const numericOids = new Set([20, 21, 23, 700, 701, 1700]);
      const dateOids = new Set([1082]);
      const timestampOids = new Set([1114, 1184]);
      const boolOid = 16;

      const workbook = new ExcelJS.Workbook();
      const dataSheet = workbook.addWorksheet("Data");
      dataSheet.addRow(fields);

      for (let colIdx = 0; colIdx < result.fields.length; colIdx++) {
        const oid = result.fields[colIdx].dataTypeID;
        if (dateOids.has(oid)) {
          dataSheet.getColumn(colIdx + 1).numFmt = 'yyyy-mm-dd';
        } else if (timestampOids.has(oid)) {
          dataSheet.getColumn(colIdx + 1).numFmt = 'yyyy-mm-dd hh:mm:ss';
        }
      }

      for (const row of result.rows) {
        dataSheet.addRow(result.fields.map((field) => {
          const val = row[field.name];
          if (val === null || val === undefined) return null;
          const oid = field.dataTypeID;
          if (numericOids.has(oid)) return Number(val);
          if (dateOids.has(oid) || timestampOids.has(oid)) return new Date(val as string);
          if (oid === boolOid) return Boolean(val);
          return val;
        }));
      }

      // Add reference sheets and data validation for xlsx downloads
      // Column offset accounts for row_id (always) + diagnostic column (error/warning only)
      const prefixColumnCount = errorColumn ? 2 : 1;
      // COLUMN_REFERENCE_MAP uses standardized English names (e.g., "primary_activity_category_code"),
      // but sourceCol has the user's original names (e.g., Norwegian "naeringskode").
      // Derive standardized names from dataCol by stripping the "_raw" suffix.
      const standardizedColumnNames = columnEntries.map(e => e.dataCol.replace(/_raw$/, ''));
      const settingsResult = await client.from("settings").select("region_version_id").single();
      const regionVersionId = settingsResult.data?.region_version_id;
      const rangeMap = await addReferenceSheets(workbook, standardizedColumnNames, client, regionVersionId);
      applyColumnValidation(dataSheet, standardizedColumnNames, rangeMap, prefixColumnCount);

      const passThrough = new PassThrough();
      const webStream = new ReadableStream({
        start(controller) {
          passThrough.on('data', (chunk: Buffer) => controller.enqueue(chunk));
          passThrough.on('end', () => { controller.close(); cleanup(); });
          passThrough.on('error', (err) => { controller.error(err); cleanup(); });
        },
        cancel() { passThrough.destroy(); cleanup(); },
      });

      workbook.xlsx.write(passThrough).then(() => passThrough.end()).catch((err) => passThrough.destroy(err));

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
