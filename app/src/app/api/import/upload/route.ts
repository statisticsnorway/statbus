import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
import { from as copyFrom } from 'pg-copy-streams';
import { Readable } from 'stream';
import ExcelJS from 'exceljs';
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

function excelValueToString(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString().split('T')[0];
  if (typeof value === 'object' && value !== null) {
    if ('result' in value) {
      const result = (value as { result: unknown }).result;
      if (result instanceof Date) return result.toISOString().split('T')[0];
      return result != null ? String(result) : '';
    }
    if ('richText' in value) {
      return (value as { richText: Array<{ text: string }> }).richText.map(rt => rt.text).join('');
    }
    if ('text' in value) {
      return String((value as { text: unknown }).text);
    }
    if ('error' in value) return '';
  }
  return String(value);
}

function csvEscapeField(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n') || value.includes('\r')) {
    return '"' + value.replace(/"/g, '""') + '"';
  }
  return value;
}

async function convertExcelToCsv(file: File): Promise<Buffer> {
  const arrayBuffer = await file.arrayBuffer();
  const workbook = new ExcelJS.Workbook();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await workbook.xlsx.load(Buffer.from(new Uint8Array(arrayBuffer)) as any);

  const worksheet = workbook.worksheets[0];
  if (!worksheet || worksheet.rowCount === 0) {
    throw new Error("Excel file appears to be empty or has no worksheets.");
  }

  const csvLines: string[] = [];
  worksheet.eachRow((row) => {
    const values: string[] = [];
    for (let i = 1; i <= worksheet.columnCount; i++) {
      const cell = row.getCell(i);
      values.push(csvEscapeField(excelValueToString(cell.value)));
    }
    csvLines.push(values.join(','));
  });

  return Buffer.from(csvLines.join('\n') + '\n', 'utf-8');
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

      // Parse header line
      const headers = headerLine.split(',')
        .map(h => h.trim())
        .filter(h => h.length > 0)
        .map(h => `"${h.replace(/"/g, '""')}"`); // Quote headers

      if (headers.length === 0) {
        throw new Error("CSV header row is empty or invalid.");
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
