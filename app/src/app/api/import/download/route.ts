import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
import { to as copyTo } from 'pg-copy-streams';
import { PassThrough } from 'stream';
import ExcelJS from 'exceljs';
import { getDbHostPort } from "@/lib/db-listener";
import type { DefinitionSnapshot } from "@/atoms/import";

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
    if (!filter || !["error", "warning"].includes(filter)) {
      return NextResponse.json({ message: "filter must be 'error' or 'warning'" }, { status: 400 });
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

    // Row number and error/warning info come first for visibility
    const errorColumn = filter === "error"
      ? `errors::text AS "_errors"`
      : `invalid_codes::text AS "_warnings"`;

    // Build WHERE clause
    const whereClause = filter === "error"
      ? `WHERE state = 'error'`
      : `WHERE invalid_codes IS NOT NULL AND invalid_codes != '{}'::jsonb`;

    const dataTable = job.data_table_name;
    const selectBody = `SELECT row_id, ${errorColumn}, ${sourceColumns} FROM ${dataTable} ${whereClause} ORDER BY row_id`;

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

    if (format === "xlsx") {
      const result = await pgClient.query(selectBody);
      const fields = result.fields.map(f => f.name);

      const workbook = new ExcelJS.Workbook();
      const worksheet = workbook.addWorksheet("Data");
      worksheet.addRow(fields);
      for (const row of result.rows) {
        worksheet.addRow(fields.map(f => row[f]));
      }

      const passThrough = new PassThrough();
      const webStream = new ReadableStream({
        start(controller) {
          passThrough.on('data', (chunk: Buffer) => controller.enqueue(chunk));
          passThrough.on('end', () => { controller.close(); cleanup(); });
          passThrough.on('error', (err) => { controller.error(err); cleanup(); });
        },
        cancel() { passThrough.destroy(); cleanup(); },
      });

      workbook.xlsx.write(passThrough).then(() => passThrough.end());

      const filename = `${slug}-${filter}s.xlsx`;
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

    const filename = `${slug}-${filter}s.csv`;
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
