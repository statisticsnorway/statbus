import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool, Client as PgClient } from 'pg'; // Import Client as PgClient to avoid name clash
import { from as copyFrom } from 'pg-copy-streams';
import { Readable } from 'stream';
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
    console.debug("dbConfig", dbConfig);
    const pool = new Pool(dbConfig);
    const pgClient = await pool.connect();

    try {
      // Begin transaction
      await pgClient.query('BEGIN');
      
      // Switch to the user's role using the JWT token
      try {
        await pgClient.query('SELECT auth.switch_role_from_jwt($1)', [accessToken]);
        logger.info(`Successfully switched to user role for import job ${job.id}`);
      } catch (error) {
        logger.error({ error }, `Failed to switch role: ${error instanceof Error ? error.message : String(error)}`);
        return NextResponse.json(
          { message: `Authentication error: ${error instanceof Error ? error.message : String(error)}` },
          { status: 403 }
        );
      }

      // --- Header Extraction ---
      // Read just enough to get the header line without loading the whole file
      const reader = file.stream().getReader();
      let headerLine = '';
      let chunkResult = await reader.read();
      let decoder = new TextDecoder();
      let buffer = '';

      while (!chunkResult.done) {
        buffer += decoder.decode(chunkResult.value, { stream: true });
        const newlineIndex = buffer.indexOf('\n');
        if (newlineIndex !== -1) {
          headerLine = buffer.substring(0, newlineIndex).trim(); // Get the first line
          // Release the lock so the stream can be used again later
          reader.releaseLock(); 
          break; // Stop reading chunks
        }
        // If buffer gets too large without finding a newline, assume error or single-line file
        if (buffer.length > 1024 * 10) { // e.g., 10KB limit for header line
           reader.releaseLock();
           throw new Error("Could not find header row within the first 10KB.");
        }
        chunkResult = await reader.read();
      }
      // Handle case where file ends before newline (single line file)
      if (!headerLine && buffer.length > 0 && chunkResult.done) {
        headerLine = buffer.trim();
        // No need to release lock here as stream is done
      }
      
      if (!headerLine) {
        throw new Error("CSV file appears to be empty or header row could not be read.");
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
      // Use COPY FROM STDIN for efficient data loading
      const copyStream = pgClient.query(copyFrom(copyCommand));
      
      // Get a *new* stream for the entire file content
      const fileStream = file.stream(); 

      // Pipe the *entire* file stream directly to the copy stream
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
            copyStream.destroy(err); // Ensure copyStream is properly terminated on abort
            reject(err);
          }
        })).then(() => {
           // fileStream piping finished successfully
           // Now wait for the copyStream to finish processing in PG
           copyStream.on('finish', resolve);
           copyStream.on('error', reject); // Handle errors during PG processing
        }).catch(err => {
           // Error during fileStream piping
           logger.error({ error: err, jobId: job.id, jobSlug: job.slug }, `File stream piping error: ${err.message}`);
           // Ensure copyStream is terminated if piping fails
           if (!copyStream.destroyed) {
             copyStream.destroy(err);
           }
           reject(err);
        });

        // Also handle errors directly on the copyStream (e.g., PG connection issues)
        copyStream.on('error', (err: Error) => {
          logger.error({ error: err, jobId: job.id, jobSlug: job.slug }, `COPY FROM stream error: ${err.message}`);
          reject(err);
        });

        copyStream.on('finish', () => {
          resolve();
        });
      });

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
