# System Stability Notifications

This document outlines the implementation plan for adding system stability notifications to inform users when data is being processed or is in a stable state.

## Overview

We'll implement a lightweight system stability indicator that shows whether the system is currently processing data or is in a stable state. This will be complemented by a detailed view that shows specific job information when requested.

## Implementation Plan

### 1. Database Components

- Create a function to efficiently check system stability
- Add notification triggers for system state changes
- Create supporting functions for detailed status information

### 2. Backend Components (Node.js/Next.js)

- Implement a persistent PostgreSQL notification listener (`pg` library) within the long-running Next.js application process (managed as a singleton).
- Create a Next.js API route using Server-Sent Events (SSE) to stream stability status updates to connected clients.
- Add a standard Next.js API route to fetch detailed job/task status information on demand for the details modal.

### 3. Frontend Components

- Create React hook for system stability status
- Implement status indicator component
- Build detailed status modal that fetches data via a standard API call when opened.

## Database Implementation

1. Create lightweight status function:
   ```sql
   CREATE OR REPLACE FUNCTION public.is_system_stable()
   RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $$
   DECLARE
       has_active_jobs boolean;
   BEGIN
       -- Fast check for any active jobs or tasks
       -- This query is optimized for speed, using EXISTS instead of COUNT
       SELECT EXISTS (
           -- Check for active import jobs
           SELECT 1 FROM public.import_job
           WHERE state NOT IN ('finished', 'rejected', 'waiting_for_review', 'waiting_for_upload')
           
           UNION ALL
           
           -- Check for active analytics tasks
           SELECT 1 FROM worker.tasks t
           JOIN worker.command_registry cr ON t.command = cr.command
           WHERE cr.queue = 'analytics' 
             AND t.state IN ('pending', 'processing')
           LIMIT 1
       ) INTO has_active_jobs;
       
       -- System is stable if no active jobs exist
       RETURN NOT has_active_jobs;
   END;
   $$;
   ```

2. Create notification trigger for system stability changes:
   ```sql
   CREATE OR REPLACE FUNCTION public.notify_system_stability_change()
   RETURNS trigger LANGUAGE plpgsql AS $$
   DECLARE
       is_stable boolean;
   BEGIN
       -- Check current system stability
       SELECT public.is_system_stable() INTO is_stable;
       
       -- Send notification with minimal payload
       PERFORM pg_notify(
           'system_stability',
           json_build_object('stable', is_stable)::text
       );
       
       RETURN NULL;
   END;
   $$;
   ```

3. Add triggers to relevant tables:
   ```sql
   CREATE TRIGGER notify_system_stability_on_import_job_change
   AFTER INSERT OR UPDATE OF state ON public.import_job
   FOR EACH STATEMENT
   EXECUTE FUNCTION public.notify_system_stability_change();

   CREATE TRIGGER notify_system_stability_on_task_change
   AFTER INSERT OR UPDATE OF state ON worker.tasks
   FOR EACH STATEMENT
   EXECUTE FUNCTION public.notify_system_stability_change();
   ```

4. Create function for detailed analytics tasks:
   ```sql
   CREATE OR REPLACE FUNCTION public.get_analytics_tasks_in_progress()
   RETURNS SETOF json LANGUAGE plpgsql SECURITY DEFINER AS $$
   BEGIN
     RETURN QUERY
     SELECT json_build_object(
       'id', t.id,
       'command', t.command,
       'state', t.state,
       'created_at', t.created_at,
       'duration_ms', t.duration_ms
     )
     FROM worker.tasks t
     JOIN worker.command_registry cr ON t.command = cr.command
     WHERE cr.queue = 'analytics' AND t.state IN ('pending', 'processing')
     ORDER BY t.priority;
   END;
   $$;
   ```

## Backend Implementation (Node.js/Next.js)

1.  **Persistent Database Listener (`lib/db-listener.ts` - Singleton):**
    Manages a single, persistent `pg` client connection that listens for `pg_notify` events. It handles connection, errors, reconnections, and distributes notifications to subscribed SSE clients.

    ```typescript
    // lib/db-listener.ts (Conceptual Example)
    import { Client } from 'pg';

    // Stores callbacks for active SSE connections
    const activeClientCallbacks = new Set<(payload: any) => void>();
    let pgClient: Client | null = null;

    async function initializeListener() {
      // Robust connection logic with retry/reconnect needed here
      pgClient = new Client({ /* connection options */ });

      pgClient.on('notification', (msg) => {
        if (msg.channel === 'system_stability' && msg.payload) {
          try {
            const payload = JSON.parse(msg.payload);
            activeClientCallbacks.forEach(callback => callback(payload));
          } catch (e) { console.error("Error processing notification", e); }
        }
        // Handle 'import_job_progress' if needed for detailed view updates
      });

      pgClient.on('error', (err) => {
        console.error('DB Listener Error:', err);
        // Implement reconnection logic
        pgClient = null;
      });

      await pgClient.connect();
      await pgClient.query('LISTEN system_stability;');
      // LISTEN import_job_progress; // If needed
      console.log('DB Listener active.');
    }

    export function addClientCallback(callback: (payload: any) => void) {
      activeClientCallbacks.add(callback);
    }

    export function removeClientCallback(callback: (payload: any) => void) {
      activeClientCallbacks.delete(callback);
    }

    // Function to get current state on demand (e.g., for initial SSE connection)
    export async function getSystemStabilityState() {
        if (!pgClient) throw new Error("Database listener not connected");
        const { rows } = await pgClient.query('SELECT public.is_system_stable() as stable;');
        return rows[0]?.stable ?? null;
    }

    // Initialize on server start
    initializeListener().catch(err => {
        console.error("Failed to initialize DB listener:", err);
        // Handle critical startup failure
    });
    ```

2.  **Server-Sent Events API Route (`app/api/system-status/live/route.ts`):**
    Handles client connections for real-time stability updates.

    ```typescript
    // app/api/system-status/live/route.ts
    import { NextResponse } from 'next/server';
    import { addClientCallback, removeClientCallback, getSystemStabilityState } from '@/lib/db-listener'; // Adjust path

    export const dynamic = 'force-dynamic'; // Ensure this route is not statically optimized

    export async function GET(request: Request) {
      const stream = new ReadableStream({
        async start(controller) {
          const handleNotification = (payload: any) => {
            controller.enqueue(`data: ${JSON.stringify(payload)}\n\n`);
          };

          // Send initial state
          try {
              const initialState = await getSystemStabilityState();
              if (initialState !== null) {
                  controller.enqueue(`data: ${JSON.stringify({ stable: initialState })}\n\n`);
              }
          } catch (err) { console.error("Error fetching initial state for SSE:", err); }

          addClientCallback(handleNotification);

          request.signal.addEventListener('abort', () => {
            removeClientCallback(handleNotification);
            controller.close();
          });
        },
        cancel() {
          // Handle stream cancellation if needed
        },
      });

      return new Response(stream, {
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      });
    }
    ```

3.  **API Route for Detailed Status (`app/api/system-status/details/route.ts`):**
    Provides detailed job/task information when requested by the modal.

    ```typescript
    // src/app/api/system-status/details/route.ts
    import { NextResponse } from 'next/server';
    import { createRouteHandlerClient } from '@supabase/auth-helpers-nextjs'; // Or your preferred DB client method
    import { cookies } from 'next/headers';

    export async function GET() {
      // Use appropriate server-side client for database access
      const supabase = createRouteHandlerClient({ cookies }); // Example using Supabase helpers

      try {
        // Get import jobs in progress
        const { data: importJobs, error: importError } = await supabase
          .from('import_job')
          .select('*')
          .not('state', 'in', '("finished","rejected","waiting_for_review","waiting_for_upload")') // Refined states
          .order('priority');

        if (importError) throw importError;

        // Get analytics tasks in progress
        const { data: analyticsTasks, error: analyticsError } = await supabase.rpc('get_analytics_tasks_in_progress');

        if (analyticsError) throw analyticsError;

        return NextResponse.json({
          import_jobs: importJobs || [],
          analytics_tasks: analyticsTasks || [],
          system_stable: (importJobs?.length === 0 && analyticsTasks?.length === 0)
        });
      } catch (error) {
        console.error("Error fetching system status details:", error);
        return NextResponse.json({ error: "Failed to fetch status details" }, { status: 500 });
      }
    }
    ```

## Frontend Implementation

1. Create React hook for system stability:
   ```typescript
   // src/hooks/useSystemStability.ts
   import { useState, useEffect } from 'react';

   export function useSystemStability() {
     const [isStable, setIsStable] = useState<boolean | null>(null);
     const [loading, setLoading] = useState(true);
     const [error, setError] = useState<string | null>(null);

     useEffect(() => {
       // Use relative URL for EventSource
       const eventSource = new EventSource('/api/system-status/live');
       setLoading(true);

       eventSource.onopen = () => {
         console.log('SSE connection opened for system stability');
         setError(null);
       };

       eventSource.onmessage = (event) => {
         try {
           const data = JSON.parse(event.data);
           setIsStable(data.stable);
           setLoading(false); // Set loading false after receiving the first valid message
         } catch (err) {
           console.error('Error parsing SSE message:', err);
           setError('Error processing status update.');
           setLoading(false);
         }
       };

       eventSource.onerror = (err) => {
         console.error('EventSource failed:', err);
         setError('Connection error. Status updates may be unavailable.');
         setLoading(false);
         setIsStable(null); // Indicate unknown state on error
         eventSource.close();
         // Consider adding retry logic here
       };

       // Cleanup function: close the connection when the component unmounts
       return () => {
         console.log('Closing SSE connection for system stability');
         eventSource.close();
       };
     }, []); // Empty dependency array ensures this runs once on mount

     return { isStable, loading, error };
   }
   ```

2. Implement status indicator component:
   ```typescript
   // src/components/SystemStatusIndicator.tsx
   import { useSystemStability } from '../hooks/useSystemStability';
   import { Badge } from './ui/badge';
   import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from './ui/tooltip';
   import { SystemStatusModal } from './SystemStatusModal';

   export function SystemStatusIndicator() {
     const { isStable, loading } = useSystemStability();
     
     if (loading) {
       return <Badge variant="outline" className="animate-pulse">Loading...</Badge>;
     }
     
     return (
       <div className="flex items-center gap-2">
         <TooltipProvider>
           <Tooltip>
             <TooltipTrigger asChild>
               <Badge 
                 variant="outline" 
                 className={isStable 
                   ? "bg-green-50 text-green-700 border-green-200" 
                   : "bg-yellow-50 text-yellow-700 border-yellow-200"
                 }
               >
                 {isStable ? "System Stable" : "Processing Data"}
               </Badge>
             </TooltipTrigger>
             <TooltipContent>
               {isStable 
                 ? "All data processing is complete" 
                 : "Data is currently being processed"
               }
             </TooltipContent>
           </Tooltip>
         </TooltipProvider>
         
         <SystemStatusModal />
       </div>
     );
   }
   ```

3. Create detailed status modal with lazy loading:
   ```typescript
   // src/components/SystemStatusModal.tsx
   import { useState, useEffect } from 'react';
   import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from './ui/dialog';
   import { Button } from './ui/button';
   import { Spinner } from './ui/spinner';
   import { Progress } from './ui/progress';

   // Define types for detailed status (adjust as needed)
   interface ImportJob {
     id: number;
     slug: string;
     state: string;
     total_rows?: number;
     imported_rows?: number;
     progress_pct?: number;
   }

   interface AnalyticsTask {
     id: number;
     command: string;
     state: string;
   }

   interface DetailedStatus {
     import_jobs: ImportJob[];
     analytics_tasks: AnalyticsTask[];
     system_stable: boolean;
   }

   export function SystemStatusModal() {
     const [open, setOpen] = useState(false);
     const [detailedStatus, setDetailedStatus] = useState<DetailedStatus | null>(null);
     const [loading, setLoading] = useState(false);
     const [error, setError] = useState<string | null>(null);

     // Fetch detailed status only when the modal is opened
     useEffect(() => {
       if (!open) {
         setDetailedStatus(null); // Clear status when closed
         setError(null);
         return;
       }

       const fetchDetailedStatus = async () => {
         setLoading(true);
         setError(null);
         try {
           const response = await fetch('/api/system-status/details'); // Use the REST API endpoint
           if (!response.ok) {
             throw new Error(`HTTP error! status: ${response.status}`);
           }
           const data: DetailedStatus = await response.json();
           setDetailedStatus(data);
         } catch (err: any) {
           console.error('Error fetching detailed status:', err);
           setError(`Failed to load details: ${err.message}`);
           setDetailedStatus(null);
         } finally {
           setLoading(false);
         }
       };

       fetchDetailedStatus();

       // Optional: Implement polling or listen to the main SSE stream
       // for hints to refresh details if needed, but avoid a dedicated
       // WebSocket connection just for this modal.

     }, [open]); // Re-run effect when 'open' state changes

     return (
       <Dialog open={open} onOpenChange={setOpen}>
         <DialogTrigger asChild>
           <Button variant="ghost" size="sm">Details</Button>
         </DialogTrigger>
         <DialogContent className="sm:max-w-[600px]">
           <DialogHeader>
             <DialogTitle>System Status Details</DialogTitle>
           </DialogHeader>
           
           {loading && <Spinner message="Loading details..." />}
           {error && <p className="text-red-600 text-center">{error}</p>}

           {detailedStatus && !loading && !error && (
             <div className="space-y-4 max-h-[60vh] overflow-y-auto p-1">
               {/* Display Import Jobs */}
               {detailedStatus.import_jobs.length > 0 ? (
                 <div>
                   <h3 className="font-medium mb-2">Import Jobs In Progress</h3>
                   <div className="space-y-3">
                     {detailedStatus.import_jobs.map(job => (
                       <div key={`import-${job.id}`} className="border rounded p-3 text-sm">
                         <div className="flex justify-between mb-1">
                           <span className="font-medium truncate pr-2" title={job.slug}>{job.slug}</span>
                           <span className="text-xs capitalize">{job.state.replace(/_/g, ' ')}</span>
                         </div>
                         {job.total_rows != null && job.total_rows > 0 && (
                           <>
                             <Progress value={job.progress_pct ?? 0} className="h-2 mb-1" />
                             <div className="text-xs text-right text-gray-600">
                               {job.imported_rows ?? 0} of {job.total_rows} rows ({job.progress_pct ?? 0}%)
                             </div>
                           </>
                         )}
                       </div>
                     ))}
                   </div>
                 </div>
               ) : (
                 !detailedStatus.analytics_tasks.length && <p className="text-sm text-gray-500">No active import jobs.</p>
               )}

               {/* Display Analytics Tasks */}
               {detailedStatus.analytics_tasks.length > 0 ? (
                 <div>
                   <h3 className="font-medium mb-2 pt-3">Analytics Tasks In Progress</h3>
                   <div className="space-y-2">
                     {detailedStatus.analytics_tasks.map(task => (
                       <div key={`task-${task.id}`} className="border rounded p-2 flex justify-between items-center text-sm">
                         <span className="truncate pr-2" title={task.command}>{task.command}</span>
                         <span className="text-xs capitalize">{task.state.replace(/_/g, ' ')}</span>
                       </div>
                     ))}
                   </div>
                 </div>
                ) : (
                 !detailedStatus.import_jobs.length && <p className="text-sm text-gray-500">No active analytics tasks.</p>
               )}

               {/* Overall Stability Footer */}
               {detailedStatus.system_stable && (
                 <div className="text-center text-green-600 pt-4 text-sm font-medium">
                   System Stable: All data processing complete.
                 </div>
               )}
                {!detailedStatus.system_stable && detailedStatus.import_jobs.length === 0 && detailedStatus.analytics_tasks.length === 0 && (
                 <div className="text-center text-yellow-600 pt-4 text-sm font-medium">
                    System may still be processing background tasks.
                 </div>
                )}
             </div>
           )}
           {!detailedStatus && !loading && !error && (
              <p className="text-center text-gray-500 py-4">Could not load status details.</p>
           )}
         </DialogContent>
       </Dialog>
     );
   }
   ```

## Testing Plan

1. Unit tests for database functions:
   - Test `is_system_stable()` and `get_analytics_tasks_in_progress()` with various system states.
   - Test notification triggers (`notify_system_stability_change`) with simulated state changes on `import_job` and `worker.tasks`.

2. Backend Integration Tests (Node.js/Next.js):
   - Test the `db-listener` singleton's ability to connect, listen, handle notifications, and manage reconnection.
   - Test the SSE API route (`/api/system-status/live`): client connection/disconnection handling, initial state sending, and forwarding of notifications from the listener.
   - Test the details API route (`/api/system-status/details`) for correct data retrieval and error handling.

3. Frontend component tests:
   - Test `useSystemStability` hook: connection via `EventSource`, state updates (`isStable`, `loading`, `error`), and cleanup.
   - Test `SystemStatusIndicator` rendering based on hook state.
   - Test `SystemStatusModal`: opening, fetching data from the details API, displaying loading/error/data states correctly.

## Deployment Considerations

1.  **Node.js Process Management:** Ensure the long-running Next.js Node process (started via `next start` in the Docker container) is monitored and restarted if it crashes (e.g., using Docker's `restart: unless-stopped` policy, which is already present).
2.  **Database Connection Robustness:** The `db-listener` singleton needs robust error handling and automatic reconnection logic for the PostgreSQL connection. Consider using connection pooling (`pg-pool`) if the listener needs to perform other queries, although a single client is sufficient for `LISTEN`.
3.  **Resource Usage:** Monitor the resource usage (CPU, memory) of the Next.js container, as it now handles persistent DB connections and SSE streaming alongside regular request processing.
4.  **SSE Connection Limits:** Be aware of potential limits on the number of concurrent open HTTP connections imposed by the server or infrastructure. SSE connections are long-lived.
5.  **Caddy Configuration:** Ensure Caddy proxy timeouts are sufficient for long-lived SSE connections (usually defaults are fine, but worth checking if issues arise). No special WebSocket configuration is needed for SSE.
6.  **Error Handling:** Implement comprehensive error handling in the listener, API routes, and frontend components. Provide informative feedback to the user when status updates are unavailable.
