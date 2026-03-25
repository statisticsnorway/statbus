import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
import { from as copyFrom } from 'pg-copy-streams';
import { Readable } from 'stream';
import { Worker } from 'node:worker_threads';
import { statfs } from 'node:fs/promises';
import Papa from 'papaparse';
import { createServerLogger } from "@/lib/server-logger";

import { getDbHostPort } from "@/lib/db-listener";

// Get database connection details for authenticator role
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

// Columns added by the download route that should be stripped on re-upload
// Include old underscore-prefixed names for backward compatibility with previously downloaded files
const DOWNLOAD_SYSTEM_COLUMNS = new Set(['row_id', 'errors', 'warnings', '_errors', '_warnings']);

function isDownloadSystemColumn(name: string): boolean {
  return DOWNLOAD_SYSTEM_COLUMNS.has(name.replace(/^"|"$/g, '').trim());
}

// Self-contained worker code for Excel→CSV conversion.
// Runs in an isolated V8 context via worker_threads — duplicates helper functions
// that can't be imported from the main module.
const EXCEL_WORKER_CODE = `
'use strict';
const { parentPort, workerData } = require('node:worker_threads');

function excelValueToString(value) {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString().split('T')[0];
  if (typeof value === 'object' && value !== null) {
    if ('result' in value) {
      const result = value.result;
      if (result instanceof Date) return result.toISOString().split('T')[0];
      return result != null ? String(result) : '';
    }
    if ('richText' in value) {
      return value.richText.map(function(rt) { return rt.text; }).join('');
    }
    if ('text' in value) {
      return String(value.text);
    }
    if ('error' in value) return '';
  }
  return String(value);
}

function csvEscapeField(value) {
  if (value.includes(',') || value.includes('"') || value.includes('\\n') || value.includes('\\r')) {
    return '"' + value.replace(/"/g, '""') + '"';
  }
  return value;
}

var DOWNLOAD_SYSTEM_COLUMNS = new Set(['row_id', 'errors', 'warnings', '_errors', '_warnings']);

function isDownloadSystemColumn(name) {
  return DOWNLOAD_SYSTEM_COLUMNS.has(name.replace(/^"|"$/g, '').trim());
}

async function convert() {
  parentPort.postMessage({ type: 'progress', phase: 'loading', rows: 0, totalRows: 0 });

  var ExcelJS = require('@protobi/exceljs');
  var workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(Buffer.from(workerData.buffer), {
    ignoreNodes: ['dataValidations'],
  });

  var worksheet = workbook.worksheets[0];
  if (!worksheet || worksheet.rowCount === 0) {
    throw new Error('Excel file appears to be empty or has no worksheets.');
  }

  parentPort.postMessage({ type: 'progress', phase: 'converting', rows: 0, totalRows: worksheet.rowCount });

  var headerRow = worksheet.getRow(1);
  var skipIndices = new Set();
  for (var i = 1; i <= worksheet.columnCount; i++) {
    var headerValue = excelValueToString(headerRow.getCell(i).value);
    if (isDownloadSystemColumn(headerValue)) {
      skipIndices.add(i);
    }
  }

  var csvLines = [];
  var rowCount = 0;
  worksheet.eachRow(function(row) {
    var values = [];
    for (var i = 1; i <= worksheet.columnCount; i++) {
      if (skipIndices.has(i)) continue;
      var cell = row.getCell(i);
      values.push(csvEscapeField(excelValueToString(cell.value)));
    }
    csvLines.push(values.join(','));
    rowCount++;
    if (rowCount % 10000 === 0) {
      parentPort.postMessage({ type: 'progress', phase: 'converting', rows: rowCount, totalRows: worksheet.rowCount });
    }
  });

  parentPort.postMessage({ type: 'result', buffer: Buffer.from(csvLines.join('\\n') + '\\n', 'utf-8') });
}

convert().catch(function(err) {
  parentPort.postMessage({ type: 'error', error: err.message || String(err) });
});
`;

const STALL_TIMEOUT_MS = 30_000;

async function convertExcelToCsv(file: File): Promise<Buffer> {
  const arrayBuffer = await file.arrayBuffer();

  return new Promise<Buffer>((resolve, reject) => {
    const worker = new Worker(EXCEL_WORKER_CODE, {
      eval: true,
      workerData: { buffer: Buffer.from(arrayBuffer) },
      resourceLimits: {
        maxOldGenerationSizeMb: 512,
      },
    });

    let settled = false;
    const settle = (fn: () => void) => {
      if (!settled) {
        settled = true;
        clearTimeout(stallTimer);
        fn();
      }
    };

    const onStall = () => {
      worker.terminate();
      settle(() => reject(new Error(
        `Excel conversion stalled (no progress for ${STALL_TIMEOUT_MS / 1000}s). ` +
        `The file may be too large or corrupted. Try converting to CSV before uploading.`
      )));
    };

    let stallTimer = setTimeout(onStall, STALL_TIMEOUT_MS);

    worker.on('message', (msg: { type: string; buffer?: Buffer; error?: string }) => {
      if (msg.type === 'progress') {
        clearTimeout(stallTimer);
        stallTimer = setTimeout(onStall, STALL_TIMEOUT_MS);
      } else if (msg.type === 'result') {
        settle(() => {
          worker.terminate();
          resolve(Buffer.from(msg.buffer!));
        });
      } else if (msg.type === 'error') {
        settle(() => {
          worker.terminate();
          reject(new Error(msg.error));
        });
      }
    });

    worker.on('error', (err) => {
      settle(() => {
        worker.terminate();
        reject(err);
      });
    });

    worker.on('exit', (code) => {
      settle(() => reject(new Error(`Excel conversion worker exited with code ${code}`)));
    });
  });
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData();
    const file = formData.get("file") as File;
    const jobSlug = formData.get("jobSlug") as string;

    if (!file) {
      return NextResponse.json(
        { message: "No file provided" },
        { status: 400 }
      );
    }

    if (!jobSlug) {
      return NextResponse.json(
        { message: "No job slug provided" },
        { status: 400 }
      );
    }

    // Dynamic disk space check: reject if file > half available space
    try {
      const stats = await statfs('/');
      const availableBytes = BigInt(stats.bavail) * BigInt(stats.bsize);
      if (BigInt(file.size) * 2n > availableBytes) {
        return NextResponse.json(
          { message: `Not enough disk space. File is ${formatSize(file.size)} but only ${formatSize(Number(availableBytes))} available. Need at least ${formatSize(file.size * 2)} free.` },
          { status: 507 }
        );
      }
    } catch {
      // statfs failure is non-fatal — continue with upload
    }

    // Get the import job details
    const client = await getServerRestClient();
    const { data: jobs, error: jobError } = await client
      .from("import_job")
      .select("*")
      .eq("slug", jobSlug);

    if (jobError || !jobs || jobs.length === 0) {
      return NextResponse.json(
        { message: `Import job not found: ${jobError?.message || "No job found with that slug"}` },
        { status: 404 }
      );
    }
    const job = jobs[0];
    // This secondary check is mostly for type safety now, primary check is above.
    if (!job) {
      return NextResponse.json(
        { message: `Import job data is invalid.` },
        { status: 404 }
      );
    }

    // Get the access token from cookies first, fail early if not present
    const accessToken = request.cookies.get('statbus')?.value;
    if (!accessToken) {
      return NextResponse.json(
        { message: "Authentication required" },
        { status: 401 }
      );
    }

    const logger = await createServerLogger();
    
    // Connect directly to PostgreSQL for efficient COPY using authenticator role
    const dbConfig = getDbConfig();
    const pool = new Pool(dbConfig);
    const pgClient = await pool.connect();

    try {
      // CRITICAL: Switch to the user's role BEFORE BEGIN transaction
      // If inside transaction, malicious SQL could ROLLBACK to become authenticator
      try {
        await pgClient.query('SELECT auth.jwt_switch_role($1)', [accessToken]);
        logger.info(`Successfully switched to user role for import job ${job.id}`);
      } catch (error) {
        logger.error({ error }, `Failed to switch role: ${error instanceof Error ? error.message : String(error)}`);
        return NextResponse.json(
          { message: `Authentication error: ${error instanceof Error ? error.message : String(error)}` },
          { status: 403 }
        );
      }

      // Begin transaction (after role is switched)
      await pgClient.query('BEGIN');

      // --- Detect file type and prepare CSV data ---
      const fileName = file.name.toLowerCase();
      const isExcel = fileName.endsWith('.xlsx');

      let csvBuffer: Buffer | null = null;
      if (isExcel) {
        csvBuffer = await convertExcelToCsv(file);
      }

      // --- Header Extraction ---
      let headerLine = '';
      if (csvBuffer) {
        const text = csvBuffer.toString('utf-8');
        const nl = text.indexOf('\n');
        headerLine = (nl !== -1 ? text.substring(0, nl) : text).trim();
      } else {
        const reader = file.stream().getReader();
        let chunkResult = await reader.read();
        const decoder = new TextDecoder();
        let buffer = '';

        while (!chunkResult.done) {
          buffer += decoder.decode(chunkResult.value, { stream: true });
          const newlineIndex = buffer.indexOf('\n');
          if (newlineIndex !== -1) {
            headerLine = buffer.substring(0, newlineIndex).trim();
            reader.releaseLock();
            break;
          }
          if (buffer.length > 1024 * 10) {
            reader.releaseLock();
            throw new Error("Could not find header row within the first 10KB.");
          }
          chunkResult = await reader.read();
        }
        if (!headerLine && buffer.length > 0 && chunkResult.done) {
          headerLine = buffer.trim();
        }
      }

      if (!headerLine) {
        throw new Error("File appears to be empty or header row could not be read.");
      }

      // Parse header line and identify system columns to strip
      const rawHeaders = headerLine.split(',')
        .map(h => h.trim())
        .filter(h => h.length > 0);

      if (rawHeaders.length === 0) {
        throw new Error("CSV header row is empty or invalid.");
      }

      // Find indices of download-added system columns (row_id, errors, warnings)
      const systemColumnIndices = new Set<number>();
      rawHeaders.forEach((h, i) => {
        if (isDownloadSystemColumn(h)) systemColumnIndices.add(i);
      });

      // If CSV has system columns, rewrite the buffer to strip them.
      // This applies to BOTH CSV and Excel uploads — Excel files already have
      // csvBuffer set from convertExcelToCsv, but system columns still need stripping.
      if (systemColumnIndices.size > 0) {
        const rawCsv = csvBuffer ? csvBuffer.toString('utf-8') : await file.text();
        const parsed = Papa.parse(rawCsv, { header: false, skipEmptyLines: false });
        const cleanedRows = (parsed.data as string[][]).map(row =>
          row.filter((_, i) => !systemColumnIndices.has(i))
        );
        csvBuffer = Buffer.from(Papa.unparse(cleanedRows, { header: false }) + '\n', 'utf-8');
      }

      const headers = rawHeaders
        .filter(h => !isDownloadSystemColumn(h))
        .map(h => `"${h.replace(/"/g, '""')}"`); // Quote headers

      if (headers.length === 0) {
        throw new Error("CSV header row contains only system columns.");
      }

      const columns = headers.join(', ');
      const copyCommand = `COPY ${job.upload_table_name} (${columns}) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',')`;
      logger.info({ jobId: job.id, jobSlug: job.slug, command: copyCommand }, `Executing COPY command`);

      // --- Data Streaming ---
      const copyStream = pgClient.query(copyFrom(copyCommand));

      if (csvBuffer) {
        // Excel path: stream converted CSV buffer to COPY
        await new Promise<void>((resolve, reject) => {
          const readable = new Readable({ read() {} });
          readable.push(csvBuffer);
          readable.push(null);
          readable.pipe(copyStream);
          copyStream.on('finish', () => resolve());
          copyStream.on('error', (err: Error) => {
            logger.error({ error: err, jobId: job.id, jobSlug: job.slug }, `COPY FROM stream error: ${err.message}`);
            reject(err);
          });
        });
      } else {
        // CSV path: stream file directly to COPY
        const fileStream = file.stream();
        await new Promise<void>((resolve, reject) => {
          fileStream.pipeTo(new WritableStream({
            write(chunk) {
              return new Promise((resolveWrite, rejectWrite) => {
                if (!copyStream.write(chunk)) {
                  copyStream.once('drain', resolveWrite);
                } else {
                  resolveWrite();
                }
              });
            },
            close() {
              copyStream.end();
            },
            abort(err) {
              copyStream.destroy(err);
              reject(err);
            }
          })).then(() => {
            copyStream.on('finish', resolve);
            copyStream.on('error', reject);
          }).catch(err => {
            logger.error({ error: err, jobId: job.id, jobSlug: job.slug }, `File stream piping error: ${err.message}`);
            if (!copyStream.destroyed) {
              copyStream.destroy(err);
            }
            reject(err);
          });

          copyStream.on('error', (err: Error) => {
            logger.error({ error: err, jobId: job.id, jobSlug: job.slug }, `COPY FROM stream error: ${err.message}`);
            reject(err);
          });

          copyStream.on('finish', () => {
            resolve();
          });
        });
      }

      // Commit transaction
      await pgClient.query('COMMIT');

      // After the upload is done the import_job will change automatically,
      // due to triggers, and the worker runs automatically,
      // due to NOTIFY by triggers.

      return NextResponse.json({
        message: "File uploaded successfully",
        jobId: job.id,
        jobSlug: job.slug
      });
    } catch (error) {
      // Rollback transaction on error
      await pgClient.query('ROLLBACK');
      logger.error({ error, jobId: job?.id, jobSlug: job?.slug }, `Error during COPY FROM transaction: ${error instanceof Error ? error.message : String(error)}`);
      throw error; // Re-throw after logging and rollback
    } finally {
      // Release the client back to the pool
      pgClient.release();
      await pool.end();
    }
  } catch (error) {
    console.error("Error in upload handler:", error);
    return NextResponse.json(
      { message: `Server error: ${error instanceof Error ? error.message : String(error)}` },
      { status: 500 }
    );
  }
}
