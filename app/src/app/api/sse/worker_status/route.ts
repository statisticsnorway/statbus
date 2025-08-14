import { addClientCallback, removeClientCallback, initializeDbListener, NotificationData } from '@/lib/db-listener';

export const dynamic = 'force-dynamic'; // Ensure this route is not statically optimized

export async function GET(request: Request) {
  // Ensure DB listener is initialized when this route is hit
  const status = await initializeDbListener();
  
  // Create a unique ID for this connection
  const connectionId = Math.random().toString(36).substring(2, 10);
  
  const stream = new ReadableStream({
    start(controller) {
      const encoder = new TextEncoder();

      // Define the callback function
      const handleNotification = function notificationHandler(data: NotificationData) {
        try {
          // Explicitly check the channel. This not only makes the handler more robust
          // but also acts as a type guard, allowing TypeScript to correctly infer
          // the shape of `data.payload` based on the channel name.
          if (data.channel === 'worker_status') {
            // The payload is already a JSON object. We send it as a standard 'message' event.
            // The client will parse this JSON and use the 'type' field to update state.
            const message = `data: ${JSON.stringify(data.payload)}\n\n`;
            controller.enqueue(encoder.encode(message));
          }
        } catch (e) {
          console.error(`SSE Route: Error sending data for client ${connectionId}:`, e);
          try { controller.close(); } catch {}
          removeClientCallback('worker_status', handleNotification);
        }
      };

      addClientCallback('worker_status', handleNotification);
      console.log(`SSE: Client ${connectionId} connected (total clients: ${status.activeCallbacks + 1})`);

      // Send an initial 'connected' event to confirm the connection is working.
      try {
        controller.enqueue(encoder.encode(`event: connected\ndata: true\n\n`));
      } catch (e) {
        console.error(`SSE Route: Error sending initial connected event for client ${connectionId}:`, e);
      }

      // Handle client disconnection
      request.signal.addEventListener('abort', () => {
        removeClientCallback('worker_status', handleNotification);
        console.log(`SSE: Client ${connectionId} disconnected.`);
        try {
          controller.close();
        } catch (e) {
          // Ignore errors if controller is already closed
        }
      });
    },
    cancel() {
      // This is less commonly used than the abort signal for client disconnections
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
    },
  });
}
