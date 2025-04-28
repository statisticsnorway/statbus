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
          jobIds, // Still useful to know which jobs the client initially requested
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
            
            logger.info({ id, verb, jobIds }, `Received import_job notification: ${verb} for job ${id}. Client tracking: ${jobIds.join(',') || 'all'}`);

            // Always process INSERT, UPDATE, DELETE notifications.
            // Clients are responsible for filtering/handling based on their needs.
            // Check if the request is still active before proceeding
            if (request.signal.aborted) {
              return;
            }

            // Process the notification regardless of the initial jobIds list
            // (Removed the outer if condition based on listenMode)
            try {
              // For DELETE operations, we don't need to fetch the job data
              if (verb === 'DELETE') {
                // Remove this job from our *local* tracking list if present (for logging/debugging)
                if (jobIds.includes(id)) {
                  jobIds = jobIds.filter(jobId => jobId !== id);
                  logger.info(`Removed deleted job (ID: ${id}) from local tracking list`);
                }

                // Send a deletion notification using the 'import_job' key
                controller.enqueue(encoder.encode(`data: ${JSON.stringify({
                  verb: 'DELETE',
                  import_job: { // Use 'import_job' key
                    id,
                    message: 'Job was deleted'
                  },
                  timestamp: new Date().toISOString()
                })}\n\n`));
              } else { // Handle INSERT and UPDATE
                // Fetch the updated job data
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

                // Structure the message with verb and import_job
                const messagePayload = {
                  verb, // Keep verb at the top level
                  import_job: data, // Use 'import_job' key for the job data object
                  timestamp: new Date().toISOString()
                };

                // Send the structured data to the client
                controller.enqueue(encoder.encode(`data: ${JSON.stringify(messagePayload)}\n\n`));
                logger.info(`Sent ${verb} notification for job ${id}`);

                // If this job is finished or rejected, and it was one we were initially tracking,
                // check if *all* initially tracked jobs are done.
                // Note: This check might be less relevant now that we send all updates,
                // but kept for potential future use or specific client needs.
                if (jobIds.includes(id) && ["finished", "rejected"].includes(data.state)) {
                  try {
                    // Check status only for the initially requested job IDs
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
                    const allTrackedDone = jobsData.every(job =>
                      ["finished", "rejected"].includes(job.state)
                    );

                    if (allTrackedDone && jobIds.length > 0) {
                      logger.info(`All initially tracked jobs (${jobIds.join(',')}) completed or rejected. Keeping SSE connection open.`);
                      // Don't close the connection - client might still be interested in new jobs.
                    }
                  } catch (err) {
                    logger.error(err, "Error checking completion status for initially tracked jobs");
                  }
                }
              } // End of INSERT/UPDATE block
            } catch (error) {
              logger.error(error, `Error processing job notification for ID: ${id}`);
            }
          } // End of channel check
        }; // End of handleNotification
      
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
