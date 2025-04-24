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

      // Send initial data for all jobs
      try {
        const { data: jobs, error } = await client
          .from("import_job")
          .select("*")
          .in("id", jobIds);

        if (error) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: "Failed to fetch jobs" })}\n\n`));
          controller.close();
          return;
        }

        // Send initial state for each job
        for (const job of jobs) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(job)}\n\n`));
        }

        // Set up a callback to listen for import_job notifications
        const handleNotification = async (notification: NotificationData) => {
          if (notification.channel === 'import_job') {
            const { id, verb } = notification.payload;
          
            // Only process updates for jobs we're tracking
            if (jobIds.includes(id) && verb === 'UPDATE') {
              // Fetch the updated job data
              const { data: updatedJob, error } = await client
                .from("import_job")
                .select("*")
                .eq("id", id)
                .single();
            
              if (error) {
                console.error("Error fetching updated job:", error);
                return;
              }
            
              // Send the updated job data to the client
              controller.enqueue(encoder.encode(`data: ${JSON.stringify(updatedJob)}\n\n`));
            
              // If this job is completed or errored, check if all jobs are done
              if (["completed", "error"].includes(updatedJob.state)) {
                // Check if all jobs are done
                const { data } = await client
                  .from("import_job")
                  .select("state")
                  .in("id", jobIds);
              
                const allDone = data?.every(job => 
                  ["completed", "error"].includes(job.state)
                );
              
                if (allDone) {
                  setTimeout(() => {
                    removeClientCallback(handleNotification);
                    controller.close();
                  }, 2000); // Give client time to process the final updates
                }
              }
            }
          }
        };
      
        // Register the callback
        addClientCallback(handleNotification);

        // Keep connection alive with heartbeat
        const heartbeat = setInterval(() => {
          controller.enqueue(encoder.encode(": heartbeat\n\n"));
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
