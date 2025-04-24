import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { addClientCallback, removeClientCallback, NotificationData } from "@/lib/db-listener";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  // Get job IDs from query parameters
  const searchParams = request.nextUrl.searchParams;
  const jobIdsParam = searchParams.get("ids");
  
  if (!jobIdsParam) {
    return NextResponse.json(
      { error: "No job IDs provided" },
      { status: 400 }
    );
  }
  
  // Parse job IDs
  const jobIds = jobIdsParam.split(",").map(id => parseInt(id.trim()));
  
  if (jobIds.length === 0 || jobIds.some(isNaN)) {
    return NextResponse.json(
      { error: "Invalid job IDs provided" },
      { status: 400 }
    );
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
        // Send a connection established message instead of initial data
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: "connection_established", jobIds })}\n\n`));
        
        if (request.signal.aborted) {
          controller.close();
          return;
        }

        // Set up a callback to listen for import_job notifications
        const handleNotification = async (notification: NotificationData) => {
          if (notification.channel === 'import_job') {
            const { id, verb } = notification.payload;
          
            // Only process updates for jobs we're tracking
            if (jobIds.includes(id) && verb === 'UPDATE') {
              // Check if the request is still active before proceeding
              if (request.signal.aborted) {
                return;
              }
              
              try {
                // Fetch the updated job data
                const { data, error } = await client
                  .from("import_job")
                  .select("*")
                  .eq("id", id)
                  .single();
              
                if (error) {
                  console.error("Error fetching updated job:", error);
                  return;
                }
              
                // Check again if the request is still active
                if (request.signal.aborted) {
                  return;
                }
                
                // Handle case where data is an array (which seems to be happening)
                const updatedJob = data;
                
                if (!updatedJob) {
                  console.error("No job data returned for ID:", id);
                  return;
                }
                
                // Send the updated job data to the client
                controller.enqueue(encoder.encode(`data: ${JSON.stringify(updatedJob)}\n\n`));
              
                // If this job is completed or errored, check if all jobs are done
                if (["completed", "error"].includes(updatedJob.state)) {
                  try {
                    // Check if all jobs are done
                    const { data } = await client
                      .from("import_job")
                      .select("state")
                      .in("id", jobIds);
                      
                    // Handle case where data is null or undefined
                    if (!data || data.length === 0) {
                      console.warn("No job data returned when checking completion status");
                      return;
                    }
                      
                    const allDone = data.every(job => 
                      ["completed", "error"].includes(job.state)
                    );
                      
                    if (allDone) {
                      console.log("All jobs completed or errored, closing SSE connection");
                      setTimeout(() => {
                        removeClientCallback(handleNotification);
                        controller.close();
                      }, 2000); // Give client time to process the final updates
                    }
                  } catch (err) {
                    console.error("Error checking job completion status:", err);
                  }
                }
              } catch (error) {
                console.error("Error processing job update:", error);
              }
            }
          }
        };
      
        // Register the callback
        addClientCallback(handleNotification);

        // Keep connection alive with heartbeat
        const heartbeat = setInterval(() => {
          try {
            if (!request.signal.aborted) {
              controller.enqueue(encoder.encode(": heartbeat\n\n"));
            } else {
              clearInterval(heartbeat);
            }
          } catch (err) {
            console.error("Heartbeat failed, controller may be closed:", err);
            clearInterval(heartbeat);
          }
        }, 30000);

        // Clean up on client disconnect
        request.signal.addEventListener("abort", () => {
          clearInterval(heartbeat);
          removeClientCallback(handleNotification);
          controller.close();
        });
      } catch (error) {
        console.error("SSE error:", error);
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: "Server error" })}\n\n`));
        controller.close();
      }
    },
  });

  return new NextResponse(stream, { headers });
}
