import { addClientCallback, removeClientCallback } from '@/lib/db-listener'; // Adjust path if needed

export const dynamic = 'force-dynamic'; // Ensure this route is not statically optimized

export async function GET(request: Request) {
  const stream = new ReadableStream({
    async start(controller) {
      // Handle notifications from the 'check' channel
      const handleNotification = (payload: string) => {
        // Send event with type 'check' and the function name as data
        try {
          controller.enqueue(`event: check\ndata: ${payload}\n\n`);
          console.log(`SSE sent: check - ${payload}`);
        } catch (e) {
          console.error("Error sending SSE data:", e);
          // Attempt to close the stream nicely on error
          try { controller.close(); } catch {}
          removeClientCallback(handleNotification);
        }
      };

      // No initial state is sent via SSE. The client fetches initial state via BaseDataStore.
      // The SSE stream only sends 'check' hints when the status *might* have changed.

      // Add the callback for this specific client connection.
      // The db-listener singleton manages the list of all active client callbacks.
      addClientCallback(handleNotification);
      console.log("SSE client connected, added callback.");

      // Handle client disconnection
      request.signal.addEventListener('abort', () => {
        console.log("SSE client disconnected, removing callback.");
        removeClientCallback(handleNotification);
        try { controller.close(); } catch {} // Close the stream on abort
      });
    },
    cancel(reason) {
      console.log("SSE stream cancelled.", reason);
      // Note: The 'abort' event listener above should handle cleanup,
      // but this cancel function is here for completeness.
      // We might need to ensure handleNotification is removed here too if abort isn't always triggered.
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      // Optional: Add CORS headers if needed, though typically same-origin
    },
  });
}
