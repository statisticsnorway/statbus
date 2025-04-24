import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
import { from as copyFrom } from 'pg-copy-streams';
import { Readable } from 'stream';
import { createServerLogger } from "@/lib/server-logger";

import { getDbHostPort } from "@/lib/db-listener";

// Get database connection details for authenticator role
const getDbConfig = () => {
  const { dbHost, dbPort, dbName } = getDbHostPort();
  return {
    host: dbHost,
    port: parseInt(dbPort),
    database: dbName,
    user: process.env.POSTGRES_AUTHENTICATOR_USER,
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
    const { data: job, error: jobError } = await client
      .from("import_job")
      .select("*")
      .eq("slug", jobSlug)
      .single();

    if (jobError || !job) {
      return NextResponse.json(
        { message: `Import job not found: ${jobError?.message || "Unknown error"}` },
        { status: 404 }
      );
    }

    // Update job state to uploading
    await client
      .from("import_job")
      .update({ 
        state: "uploading",
        import_completed_pct: 0
      })
      .eq("id", job.id);

    // Read file content
    const fileBuffer = await file.arrayBuffer();
    const fileContent = new TextDecoder().decode(fileBuffer);

    // Create a readable stream from the file content
    const fileStream = Readable.from([fileContent]);

    // Get the access token from cookies
    const accessToken = request.cookies.get('statbus')?.value;
    if (!accessToken) {
      return NextResponse.json(
        { message: "Authentication required" },
        { status: 401 }
      );
    }

    const logger = await createServerLogger();
    
    // Connect directly to PostgreSQL for efficient COPY using authenticator role
    const pool = new Pool(getDbConfig());
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

      // Use COPY FROM STDIN for efficient data loading
      const copyStream = pgClient.query(
        copyFrom(`COPY ${job.upload_table_name} FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',')`)
      );

      // Set up progress tracking
      let totalBytes = fileContent.length;
      let bytesSent = 0;
      let lastProgressUpdate = 0;

      // Pipe the file content to the copy stream with progress tracking
      await new Promise<void>((resolve, reject) => {
        fileStream.on('data', async (chunk) => {
          bytesSent += chunk.length;
          
          // Update progress every 5%
          const progress = Math.floor((bytesSent / totalBytes) * 100);
          if (progress >= lastProgressUpdate + 5) {
            lastProgressUpdate = progress;
            
            // Update job progress
            await client
              .from("import_job")
              .update({ import_completed_pct: progress })
              .eq("id", job.id);
          }
          
          if (!copyStream.write(chunk)) {
            fileStream.pause();
          }
        });

        copyStream.on('drain', () => {
          fileStream.resume();
        });

        fileStream.on('end', () => {
          copyStream.end();
        });

        copyStream.on('error', (err) => {
          reject(err);
        });

        copyStream.on('finish', () => {
          resolve();
        });
      });

      // Commit transaction
      await pgClient.query('COMMIT');

      // Update job state to processing
      const { error: updateError } = await client
        .from("import_job")
        .update({ 
          state: "processing",
          import_completed_pct: 100
        })
        .eq("id", job.id);

      if (updateError) {
        return NextResponse.json(
          { message: `Error updating job state: ${updateError.message}` },
          { status: 500 }
        );
      }

      return NextResponse.json({ 
        message: "File uploaded successfully",
        jobId: job.id,
        jobSlug: job.slug
      });
    } catch (error) {
      // Rollback transaction on error
      await pgClient.query('ROLLBACK');
      throw error;
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
