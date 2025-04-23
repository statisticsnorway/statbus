import { addClientCallback, removeClientCallback, initializeDbListener } from '@/lib/db-listener'; // Adjust path if needed

export const dynamic = 'force-dynamic'; // Ensure this route is not statically optimized

export async function GET(request: Request) {
  // Ensure DB listener is initialized when this route is hit
  const status = await initializeDbListener();
  
  // Create a unique ID for this connection
  const connectionId = Math.random().toString(36).substring(2, 10);
  
  const stream = new ReadableStream({
    start(controller) {
      // Define the callback function
      const handleNotification = function notificationHandler(payload: string) {
        try {
          const message = `event: check\ndata: ${payload}\n\n`;
          controller.enqueue(new TextEncoder().encode(message));
        } catch (e) {
          console.error(`SSE Route: Error sending data:`, e);
          try { controller.close(); } catch {}
          removeClientCallback(handleNotification);
        }
      };

      // No initial state is sent via SSE. The client fetches initial state via BaseDataStore.
      // The SSE stream only sends 'check' hints when the status *might* have changed.

      // Add the callback for this specific client connection
      addClientCallback(handleNotification);
      console.log(`SSE: Client ${connectionId} connected (total clients: ${status.activeCallbacks + 1})`);

      // Send an initial ping to confirm connection is working
      try {
        controller.enqueue(new TextEncoder().encode(`event: connected\ndata: true\n\n`));
      } catch (e) {
        console.error(`SSE Route: Error sending initial ping:`, e);
      }

      // Handle client disconnection (e.g., browser tab closed)
      request.signal.addEventListener('abort', () => {
        removeClientCallback(handleNotification);
        try {
          controller.close();
        } catch (e) {
          // Ignore errors closing an already closed controller
        }
      });
    },
    cancel() {
      // This might be called if the stream is cancelled programmatically
      // We'll rely on the abort signal for cleanup
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
