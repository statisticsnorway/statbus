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
  const scopeParam = searchParams.get("scope");
  const scope = (scopeParam === 'updates_for_ids_only') ? 'updates_for_ids_only' : 'updates_and_all_inserts';
  
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
          scope,
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
          // Assert that we are only handling the correct channel's notifications.
          if (notification.channel !== 'import_job') {
            return;
          }

          if (request.signal.aborted) {
            return;
          }

          const { verb, import_job } = notification.payload;
          const id = import_job.id;

          // Server-side filtering logic based on subscription scope.
          if (scope === 'updates_for_ids_only') {
            // Scope for pages that only care about specific jobs (e.g., job data page).
            // Only send notifications for the job IDs the client is explicitly tracking.
            if (jobIds.length === 0 || !jobIds.includes(id)) {
              if (process.env.NODE_ENV === 'development') {
                logger.info({ id, verb, jobIds, scope }, `Skipping notification for client as job ID is not tracked in 'updates_for_ids_only' scope.`);
              }
              return; // Skip this notification for this client
            }
          } else { // Default scope: 'updates_and_all_inserts'
            // Scope for the main jobs list page.
            // It should receive all INSERTs, but only UPDATEs/DELETEs for tracked jobs.
            if (jobIds.length > 0 && verb !== 'INSERT' && !jobIds.includes(id)) {
              if (process.env.NODE_ENV === 'development') {
                logger.info({ id, verb, jobIds, scope }, `Skipping non-INSERT notification for client as job ID is not tracked.`);
              }
              return; // Skip this notification for this client
            }
          }
          
          logger.info({ id, verb, jobIds }, `Received enriched import_job notification. Forwarding to client.`);

          // Add a timestamp and send the payload
          const messagePayload = {
            ...notification.payload,
            timestamp: new Date().toISOString()
          };

          controller.enqueue(encoder.encode(`data: ${JSON.stringify(messagePayload)}\n\n`));
        }; // End of handleNotification
      
        // Register the callback for the 'import_job' channel
        addClientCallback('import_job', handleNotification);
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
          removeClientCallback('import_job', handleNotification);
          logger.info("Client disconnected, cleaned up SSE resources for import_job");
          
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
