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

1. Create lightweight status functions:
   - **Specific Task Status:** For granular UI feedback, use these functions (accessible via `/rest/rpc/...`):
     - `public.is_importing()`: Returns `true` if any import jobs (`import_job_process`) are pending or processing.
     - `public.is_deriving_statistical_units()`: Returns `true` if the core statistical unit derivation (`derive_statistical_unit`) is pending, processing, or **waiting** (parent awaiting children).
     - `public.is_deriving_reports()`: Returns `true` if report/facet derivation (`derive_reports`) is pending, processing, or **waiting**.

   ```sql
   -- Specific task status checks (in public schema)
   CREATE FUNCTION public.is_importing() RETURNS boolean ...;
   CREATE FUNCTION public.is_deriving_statistical_units() RETURNS boolean ...;
   CREATE FUNCTION public.is_deriving_reports() RETURNS boolean ...;
   -- (See migration 20250422155400 for full definitions)
   ```

2. Create notification mechanism:
   - **Direct Status Notification:** The `worker.process_tasks` procedure calls optional `before_procedure` (e.g., `worker.notify_is_importing_start`) and `after_procedure` (e.g., `worker.notify_is_importing_stop`) hooks defined in `worker.command_registry`. These hooks are responsible for sending notifications on the `worker_status` channel when specific tasks start and finish.
   - **Payload:** The payload sent on the `worker_status` channel is a JSON object containing the status type and a hardcoded boolean value, for example: `{"type": "is_importing", "status": true}`. This provides the state directly to the client without needing to call the slow `is_importing()` function.

   ```sql
   -- Example notification procedures (called by before/after hooks)
   CREATE PROCEDURE worker.notify_is_importing_start()
   LANGUAGE plpgsql AS $procedure$
   BEGIN
     PERFORM pg_notify('worker_status', json_build_object('type', 'is_importing', 'status', true)::text);
   END;
   $procedure$;

   CREATE PROCEDURE worker.notify_is_importing_stop()
   LANGUAGE plpgsql AS $procedure$
   BEGIN
     PERFORM pg_notify('worker_status', json_build_object('type', 'is_importing', 'status', false)::text);
   END;
   $procedure$;

   -- Example registration in command_registry
   INSERT INTO worker.command_registry (..., before_procedure, after_procedure, ...)
   VALUES (..., 'worker.notify_is_importing_start', 'worker.notify_is_importing_stop', ...);
   ```
   *Note: The `worker_status` notification provides the hardcoded boolean status for `is_importing`, `is_deriving_statistical_units`, or `is_deriving_reports`, eliminating calls to the status functions and client-side re-querying.*

3. Create function for detailed *analytics* tasks (already exists, shown for context):
   ```sql
   CREATE OR REPLACE FUNCTION public.get_analytics_tasks_in_progress()
   RETURNS SETOF json LANGUAGE plpgsql SECURITY DEFINER AS $$
   BEGIN
     RETURN QUERY
     SELECT json_build_object(
       'id', t.id,
       'command', t.command, -- e.g., 'derive_statistical_unit', 'derive_reports'
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
    **Security Note:** This listener connects with a dedicated, read-only database user (`POSTGRES_NOTIFY_USER`) that has minimal privileges. It can only listen for notifications and read from a few specific tables to enrich the notification payloads. This follows the Principle of Least Privilege.

    ```typescript
    // lib/db-listener.ts (Conceptual Example with Debouncing)
    import { Client } from 'pg';

    type StatusPayload = { type: string; status: boolean };

    // Stores callbacks for active SSE connections
    const activeClientCallbacks = new Set<(payload: StatusPayload) => void>();
    let pgClient: Client | null = null;

    // State for debouncing notifications
    const debounceTimers: { [key: string]: NodeJS.Timeout } = {};
    const DEBOUNCE_DELAY_MS = 500;

    function handleNotification(payload: StatusPayload) {
      // Clear any pending timer for this status type
      if (debounceTimers[payload.type]) {
        clearTimeout(debounceTimers[payload.type]);
      }

      // Set a new timer. If another notification for the same type arrives
      // before the timer fires, it will be cleared and replaced.
      debounceTimers[payload.type] = setTimeout(() => {
        // Send the latest status to all connected clients
        activeClientCallbacks.forEach(callback => callback(payload));
        delete debounceTimers[payload.type]; // Clean up timer
      }, DEBOUNCE_DELAY_MS);
    }

    async function initializeListener() {
      // Robust connection logic with retry/reconnect needed here
      pgClient = new Client({ /* connection options */ });

      pgClient.on('notification', (msg) => {
        if (msg.channel === 'worker_status' && msg.payload) {
          try {
            const payload: StatusPayload = JSON.parse(msg.payload);
            handleNotification(payload); // Pass to debouncing handler
          } catch (e) {
            console.error("Failed to parse worker_status notification payload:", e);
          }
        }
      });

      pgClient.on('error', (err) => {
        console.error('DB Listener Error:', err);
        // Implement reconnection logic
        pgClient = null;
      });

      await pgClient.connect();
      await pgClient.query('LISTEN worker_status;');
      console.log('DB Listener active for worker_status channel.');
    }

    export function addClientCallback(callback: (payload: StatusPayload) => void) {
      activeClientCallbacks.add(callback);
    }

    export function removeClientCallback(callback: (payload: StatusPayload) => void) {
      activeClientCallbacks.delete(callback);
    }

    // No initial state fetch needed as we don't have a general stability status anymore

    // The initializeDbListener() function should be called once during server startup.
    // This is typically done in `instrumentation.ts`.
    ```

2.  **Server-Sent Events API Route (`app/api/sse/worker-status/route.ts`):**
    Handles client connections for real-time status update notifications.

    ```typescript
    // app/api/sse/worker-status/route.ts
    import { NextResponse } from 'next/server';
    import { addClientCallback, removeClientCallback } from '@/lib/db-listener'; // Adjust path

    export const dynamic = 'force-dynamic'; // Ensure this route is not statically optimized

    type StatusPayload = { type: string; status: boolean };

    export async function GET(request: Request) {
      const stream = new ReadableStream({
        async start(controller) {
          // Handle notifications from the 'worker_status' channel
          const handleNotification = (payload: StatusPayload) => {
            // Send a standard 'message' event with the JSON payload as data.
            // The client will use the 'type' field inside the JSON to update its state.
            controller.enqueue(`data: ${JSON.stringify(payload)}\n\n`);
          };

          // No initial state to send

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

1. Centralized Status Management (`app/src/app/BaseDataClient.tsx`):
   - The `ClientBaseDataProvider` component manages the Server-Sent Events (`EventSource`) connection to `/api/sse/worker-status`.
   - It listens for `message` events, which contain a JSON payload like `{"type": "is_importing", "status": true}`.
   - When an event is received, it parses the payload and updates a client-side state store (e.g., Zustand) directly with the new boolean status for the given type, eliminating any need for follow-up API calls.
   - It subscribes to status updates within the state store and updates its own state to reflect the latest `derivationStatus` (isDerivingUnits, isDerivingReports, isLoading, error).
   - This `derivationStatus` is provided via the `BaseDataClientContext`.

   ```typescript
   // Simplified conceptual flow within ClientBaseDataProvider
   useEffect(() => {
     const eventSource = new EventSource('/api/sse/worker-status'); // Use updated path
     
     // Listen for generic messages
     eventSource.onmessage = (event) => {
       try {
         const statusUpdate = JSON.parse(event.data);
         // Update the zustand store directly with the new status
         // The store would have a method like `setDerivationStatus(type, status)`
         baseDataStore.setDerivationStatus(statusUpdate.type, statusUpdate.status);
       } catch (e) {
         console.error("Failed to parse worker status update:", e);
       }
     };

     // ... error handling, cleanup ...

     // Subscribe to store updates to reflect them in the component's context
     const unsubscribe = baseDataStore.subscribeDerivationStatus(() => {
       setDerivationStatus(baseDataStore.getDerivationStatus()); // Update local state from store
     });
     return unsubscribe;
   }, []);

   // Context value includes the derivationStatus state
   const contextValue = { /* ... other base data ..., */ derivationStatus };
   return <BaseDataClientContext.Provider value={contextValue}>...</BaseDataClientContext.Provider>;
   ```

2. Consuming Status in Components:
   - Components needing to react to derivation status changes use the `useBaseData` hook to access the `derivationStatus` object from the context.
   - No separate notification hook or triggers are needed in individual components.

   ```typescript
   // Example: src/app/import/analyse-data-for-search-and-reports/statistical-units-refresher.tsx
   import { useBaseData } from "@/app/BaseDataClient";

   function StatisticalUnitsRefresher() {
     const { derivationStatus, hasStatisticalUnits, refreshHasStatisticalUnits } = useBaseData();
     const { isDerivingUnits, isDerivingReports, isLoading, error } = derivationStatus;

     useEffect(() => {
       if (isLoading) { /* Show checking spinner */ }
       else if (error) { /* Show error */ }
       else if (isDerivingUnits || isDerivingReports) { /* Show deriving spinner */ }
       else {
         // Derivation finished, check hasStatisticalUnits
         refreshHasStatisticalUnits().then(hasUnits => {
           if (hasUnits) { /* Show finished */ }
           else { /* Show failed - no units found */ }
         });
       }
     }, [derivationStatus, refreshHasStatisticalUnits]);

     // ... render based on state ...
   }
   ```

3. Implement status indicator component:
   ```typescript
   // src/components/SystemStatusIndicator.tsx
   import { SystemStatusModal } from './SystemStatusModal'; // Assumes this modal exists

   // Simplified indicator - only shows the button to open the details modal
   export function SystemStatusIndicator() {
     return (
       <div className="flex items-center gap-2">
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
   - Test `public.is_importing()`, `public.is_deriving_statistical_units()`, `public.is_deriving_reports()` with various system states to ensure they are still correct for initial page loads.
   - Test `worker.process_tasks` to ensure it correctly calls registered `before_procedure` and `after_procedure` hooks.
   - Test the specific hook procedures (e.g., `worker.notify_is_importing_start`, `worker.notify_is_importing_stop`) to ensure they call `pg_notify('worker_status', '{"type": "is_importing", "status": true/false}')` with the correct hardcoded boolean.
   - Test the registration of the `_start` and `_stop` hooks in `worker.command_registry`.

2. Backend Integration Tests (Node.js/Next.js):
   - Test the `db-listener` singleton's ability to connect, listen to the `worker_status` channel, handle JSON notifications, and manage reconnection.
   - Test the **debouncing logic** in the listener: send rapid-fire notifications and assert that only the last one is sent to the client callback after the delay.
   - Test the SSE API route (`/api/sse/worker-status`): client connection/disconnection handling and forwarding of the debounced JSON payload.
   - Test the details API route (`/api/system-status/details`) for correct data retrieval.

3. Frontend component tests:
   - Test `ClientBaseDataProvider`: Ensure `EventSource` connects to `/api/sse/worker-status`, and on `message` events, it correctly parses the JSON payload and calls the state store's update function (e.g., `baseDataStore.setDerivationStatus(type, status)`).
   - Test `SystemStatusIndicator` rendering (it's now just the modal trigger).
   - Test `SystemStatusModal`: opening, fetching data from the details API, displaying loading/error/data states correctly.
   - Test components consuming `useBaseData` (like `StatisticalUnitsRefresher`) to ensure they react correctly to the direct status updates provided by the context, without making any extra API calls.

## Deployment Considerations

1.  **Initialization:** The `initializeDbListener()` function is called from `instrumentation.ts` to ensure the listener starts when the Next.js server process boots up.
2.  **Node.js Process Management:** Ensure the long-running Next.js Node process (started via `next start` in the Docker container) is monitored and restarted if it crashes (e.g., using Docker's `restart: unless-stopped` policy, which is already present).
3.  **Database Connection Robustness:** The `db-listener` singleton needs robust error handling and automatic reconnection logic for the PostgreSQL connection. A single client is sufficient for `LISTEN`.
4.  **Resource Usage:** Monitor the resource usage (CPU, memory) of the Next.js container, as it now handles a persistent DB connection and SSE streaming alongside regular request processing.
4.  **SSE Connection Limits:** Be aware of potential limits on the number of concurrent open HTTP connections imposed by the server or infrastructure. SSE connections are long-lived.
5.  **Caddy Configuration:** Ensure Caddy proxy timeouts are sufficient for long-lived SSE connections (usually defaults are fine, but worth checking if issues arise). No special WebSocket configuration is needed for SSE.
6.  **Error Handling:** Implement comprehensive error handling in the listener, API routes, and frontend components. Provide informative feedback to the user when status updates are unavailable.
