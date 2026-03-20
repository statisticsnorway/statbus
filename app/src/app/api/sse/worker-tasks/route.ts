import { addClientCallback, removeClientCallback, initializeDbListener, NotificationData } from '@/lib/db-listener';

export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  await initializeDbListener();

  const stream = new ReadableStream({
    start(controller) {
      const encoder = new TextEncoder();

      const handleNotification = function notificationHandler(data: NotificationData) {
        try {
          if (data.channel === 'worker_task_changed') {
            const message = `data: ${JSON.stringify(data.payload)}\n\n`;
            controller.enqueue(encoder.encode(message));
          }
        } catch (e) {
          console.error('SSE worker-tasks: Error sending data:', e);
          try { controller.close(); } catch {}
          removeClientCallback('worker_task_changed', handleNotification);
        }
      };

      addClientCallback('worker_task_changed', handleNotification);

      try {
        controller.enqueue(encoder.encode(`event: connected\ndata: true\n\n`));
      } catch {}

      const heartbeat = setInterval(() => {
        try {
          if (!request.signal.aborted) {
            controller.enqueue(encoder.encode(": heartbeat\n\n"));
          } else {
            clearInterval(heartbeat);
          }
        } catch {
          clearInterval(heartbeat);
          try { controller.close(); } catch {}
          removeClientCallback('worker_task_changed', handleNotification);
        }
      }, 30000);

      request.signal.addEventListener('abort', () => {
        clearInterval(heartbeat);
        removeClientCallback('worker_task_changed', handleNotification);
        try { controller.close(); } catch {}
      });
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
