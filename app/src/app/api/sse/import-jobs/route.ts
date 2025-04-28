import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { addClientCallback, removeClientCallback, NotificationData } from "@/lib/db-listener";
import { createServerLogger } from "@/lib/server-logger";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const logger = await createServerLogger();
  
  // Get job IDs from query parameters
  const searchParams = request.nextUrl.searchParams;
  const jobIdsParam = searchParams.get("ids");
  
  // Initialize jobIds array
  let jobIds: number[] = [];
  
  // If IDs are provided, parse them
  if (jobIdsParam) {
    try {
      jobIds = jobIdsParam.split(",")
        .map(id => id.trim())
        .filter(id => id !== "0" && id !== "") // Filter out "0" and empty strings
        .map(id => {
          const parsed = parseInt(id);
          if (isNaN(parsed) || parsed <= 0) {
            throw new Error(`Invalid job ID: ${id}`);
          }
          return parsed;
        });
    } catch (error) {
      logger.error(error, "Error parsing job IDs");
      return NextResponse.json(
        { error: "Invalid job ID format" },
        { status: 400 }
      );
    }
  }
  
  // If no valid IDs provided, we'll still continue but only listen for INSERTs
  const listenMode = jobIds.length === 0 ? "insert_only" : "track_jobs";

  // Set up SSE headers
  const headers = new Headers({
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache, no-transform",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no" // Prevents Nginx from buffering the response
  });

  const stream = new ReadableStream({
    async start(controller) {
      const encoder = new TextEncoder();
      const client = await getServerRestClient();

      try {
        // Send a connection established message with timestamp and more details
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ 
          type: "connection_established", 
          jobIds,
          listenMode,
          timestamp: new Date().toISOString(),
          connectionId: Math.random().toString(36).substring(2, 10), // Simple connection ID for debugging
          serverInfo: {
            version: process.env.VERSION || 'unknown',
            environment: process.env.NODE_ENV || 'development'
          }
        })}\n\n`));
        
        // Also send an initial retry directive to help clients with reconnection
        controller.enqueue(encoder.encode("retry: 3000\n\n"));
        
        if (request.signal.aborted) {
          controller.close();
          return;
        }

        // Set up a callback to listen for import_job notifications
        const handleNotification = async (notification: NotificationData) => {
          if (notification.channel === 'import_job') {
            const { id, verb } = notification.payload;
            
            logger.info({ id, verb }, `Received import_job notification: ${verb} for job ${id}`);
          
            // Process notifications based on listen mode
            // In insert_only mode, we only care about INSERT notifications
            // In track_jobs mode, we care about INSERT, UPDATE, and DELETE for tracked jobs
            if (verb === 'INSERT' || (listenMode === "track_jobs" && jobIds.includes(id) && (verb === 'UPDATE' || verb === 'DELETE'))) {
              // Check if the request is still active before proceeding
              if (request.signal.aborted) {
                return;
              }
              
              // For DELETE operations, we don't need to fetch the job data
              if (verb === 'DELETE') {
                // Remove this job from our tracking list
                jobIds = jobIds.filter(jobId => jobId !== id);
                logger.info(`Removed deleted job (ID: ${id}) from tracking list`);
                
                // Send a deletion notification to the client with the verb explicitly included
                controller.enqueue(encoder.encode(`data: ${JSON.stringify({
                  id,
                  verb: 'DELETE',
                  message: 'Job was deleted',
                  timestamp: new Date().toISOString()
                })}\n\n`));
                
                return;
              }
              
              try {
                // Fetch the updated job data for INSERT/UPDATE operations
                const { data, error } = await client
                  .from("import_job")
                  .select("*")
                  .eq("id", id)
                  .single();
              
                if (error) {
                  logger.error(error, `Error fetching updated job: ${id}`);
                  return;
                }
              
                // Check again if the request is still active
                if (request.signal.aborted) {
                  return;
                }
                
                if (!data) {
                  logger.error(`No job data returned for ID: ${id}`);
                  return;
                }
                
                // Add the verb to the job data before sending
                const jobWithVerb = {
                  ...data,
                  verb // Explicitly include the verb in the payload
                };
                
                // Send the updated job data to the client
                controller.enqueue(encoder.encode(`data: ${JSON.stringify(jobWithVerb)}\n\n`));
                logger.info(`Sent ${verb} notification for job ${id}`);
              
                // For INSERT notifications in track_jobs mode, check if this is a job we should track
                if (listenMode === "track_jobs" && verb === 'INSERT' && !jobIds.includes(id)) {
                  // Check if the job slug matches our pattern
                  if (data.slug && data.slug.startsWith('import_')) {
                    // Add this job to our tracking list
                    jobIds.push(id);
                    logger.info(`Added new job ${data.slug} (ID: ${id}) to tracking list`);
                  }
                }
                
                // If this job is finished or rejected, check if all jobs are done
                if (["finished", "rejected"].includes(data.state)) {
                  try {
                    // Check if all jobs are done
                    const { data: jobsData } = await client
                      .from("import_job")
                      .select("state")
                      .in("id", jobIds);
                      
                    // Handle case where data is null or undefined
                    if (!jobsData || jobsData.length === 0) {
                      logger.warn("No job data returned when checking completion status");
                      return;
                    }
                      
                    const allDone = jobsData.every(job => 
                      ["finished", "rejected"].includes(job.state)
                    );
                      
                    if (allDone) {
                      logger.info("All jobs completed or rejected, but keeping SSE connection open for new jobs");
                      // Don't close the connection - keep listening for new jobs
                    }
                  } catch (err) {
                    logger.error(err, "Error checking job completion status");
                  }
                }
              } catch (error) {
                logger.error(error, `Error processing job update for ID: ${id}`);
              }
            }
          }
        };
      
        // Register the callback
        addClientCallback(handleNotification);
        logger.info("Registered SSE callback for import jobs");

        // Keep connection alive with heartbeat and connection status monitoring
        let missedHeartbeats = 0;
        const heartbeat = setInterval(() => {
          try {
            if (!request.signal.aborted) {
              // Send heartbeat with more info
              controller.enqueue(encoder.encode(
                "event: heartbeat\n" +
                `data: ${JSON.stringify({
                  type: "heartbeat",
                  timestamp: new Date().toISOString(),
                  jobCount: jobIds.length,
                  connectionId: Math.random().toString(36).substring(2, 10) // Simple connection ID for debugging
                })}\n\n`
              ));
              
              // Reset missed heartbeats counter on successful send
              missedHeartbeats = 0;
            } else {
              logger.info("Request aborted, clearing heartbeat interval");
              clearInterval(heartbeat);
            }
          } catch (err) {
            logger.error(err, "Heartbeat failed, controller may be closed");
            missedHeartbeats++;
            
            // If we've missed too many heartbeats, close the connection
            if (missedHeartbeats >= 3) {
              logger.warn("Too many missed heartbeats, closing connection");
              clearInterval(heartbeat);
              try {
                controller.close();
              } catch (closeErr) {
                logger.error(closeErr, "Error closing controller after missed heartbeats");
              }
            }
          }
        }, 10000); // Heartbeats every 10 seconds

        // Clean up on client disconnect
        request.signal.addEventListener("abort", () => {
          clearInterval(heartbeat);
          removeClientCallback(handleNotification);
          logger.info("Client disconnected, cleaned up SSE resources");
          
          try {
            controller.close();
          } catch (err) {
            logger.error(err, "Error closing controller during cleanup");
          }
        });
      } catch (error) {
        logger.error(error, "SSE error");
        
        try {
          // Send error message to client
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ 
            error: "Server error", 
            message: error instanceof Error ? error.message : String(error),
            timestamp: new Date().toISOString()
          })}\n\n`));
          
          // Close the controller
          controller.close();
        } catch (closeErr) {
          logger.error(closeErr, "Error sending error message or closing controller");
        }
      }
    },
  });

  return new NextResponse(stream, { headers });
}
