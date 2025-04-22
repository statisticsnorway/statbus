# System Stability Notifications

This document outlines the implementation plan for adding system stability notifications to inform users when data is being processed or is in a stable state.

## Overview

We'll implement a lightweight system stability indicator that shows whether the system is currently processing data or is in a stable state. This will be complemented by a detailed view that shows specific job information when requested.

## Implementation Plan

### 1. Database Components

- Create a function to efficiently check system stability
- Add notification triggers for system state changes
- Create supporting functions for detailed status information

### 2. Backend Components

- Implement WebSocket server in Crystal for real-time notifications
- Create separate channels for lightweight status and detailed information
- Add API endpoint for detailed status information

### 3. Frontend Components

- Create React hook for system stability status
- Implement status indicator component
- Build detailed status modal with lazy loading

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

## Crystal WebSocket Server

1. Extend the worker.cr file to include WebSocket handling:
   ```crystal
   module Statbus
     class WorkerMonitor
       @stability_sockets = [] of HTTP::WebSocket
       @detail_sockets = [] of HTTP::WebSocket
       
       def initialize_websocket
         # Lightweight stability status WebSocket
         ws "/api/system-stability" do |socket|
           # Send initial stability status
           initial_status = get_system_stability
           socket.send({stable: initial_status}.to_json)
           
           @stability_sockets << socket
           
           socket.on_close do
             @stability_sockets.delete(socket)
           end
         end
         
         # Detailed job status WebSocket (only used when details view is open)
         ws "/api/job-details" do |socket|
           # Send initial detailed status
           initial_details = get_detailed_status
           socket.send(initial_details.to_json)
           
           @detail_sockets << socket
           
           socket.on_close do
             @detail_sockets.delete(socket)
           end
         end
         
         # Listen for PostgreSQL notifications
         spawn monitor_pg_notifications
       end
       
       private def monitor_pg_notifications
         PG.connect_listen(@config.connection_string, 
                           channels: ["system_stability", "import_job_progress"]) do |notification|
           case notification.channel
           when "system_stability"
             # Broadcast lightweight status to all stability sockets
             broadcast_to_stability_clients(notification.payload)
             
             # Also update detail sockets if any are connected
             if !@detail_sockets.empty?
               details = get_detailed_status
               broadcast_to_detail_clients(details.to_json)
             end
             
           when "import_job_progress"
             # Only broadcast to detail sockets
             if !@detail_sockets.empty?
               broadcast_to_detail_clients(notification.payload)
             end
           end
         end
       end
     end
   end
   ```

## Frontend Implementation

1. Create React hook for system stability:
   ```typescript
   // src/hooks/useSystemStability.ts
   import { useState, useEffect } from 'react';
   import { createClient } from '@supabase/supabase-js';

   export function useSystemStability() {
     const [isStable, setIsStable] = useState<boolean | null>(null);
     const [loading, setLoading] = useState(true);
     
     useEffect(() => {
       // Initial status fetch via API
       const fetchInitialStatus = async () => {
         try {
           const supabase = createSupabaseClient();
           const { data } = await supabase.rpc('is_system_stable');
           setIsStable(data);
         } catch (err) {
           console.error('Error fetching system stability:', err);
         } finally {
           setLoading(false);
         }
       };
       
       fetchInitialStatus();
       
       // Set up WebSocket connection for lightweight updates
       const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
       const wsUrl = `${protocol}//${window.location.host}/api/system-stability`;
       const socket = new WebSocket(wsUrl);
       
       socket.onmessage = (event) => {
         try {
           const data = JSON.parse(event.data);
           setIsStable(data.stable);
         } catch (err) {
           console.error('Error parsing WebSocket message:', err);
         }
       };
       
       return () => {
         socket.close();
       };
     }, []);
     
     return { isStable, loading };
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

   export function SystemStatusModal() {
     const [open, setOpen] = useState(false);
     const [detailedStatus, setDetailedStatus] = useState(null);
     const [loading, setLoading] = useState(false);
     const [socket, setSocket] = useState<WebSocket | null>(null);
     
     // Only connect to WebSocket when modal is open
     useEffect(() => {
       if (!open) {
         // Close socket when modal closes
         if (socket) {
           socket.close();
           setSocket(null);
         }
         return;
       }
       
       // Fetch initial data and open WebSocket when modal opens
       setLoading(true);
       
       const fetchDetailedStatus = async () => {
         try {
           const response = await fetch('/api/system-status-details');
           const data = await response.json();
           setDetailedStatus(data);
         } catch (err) {
           console.error('Error fetching detailed status:', err);
         } finally {
           setLoading(false);
         }
       };
       
       fetchDetailedStatus();
       
       // Set up WebSocket for detailed updates
       const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
       const wsUrl = `${protocol}//${window.location.host}/api/job-details`;
       const newSocket = new WebSocket(wsUrl);
       
       newSocket.onmessage = (event) => {
         try {
           const data = JSON.parse(event.data);
           setDetailedStatus(data);
         } catch (err) {
           console.error('Error parsing WebSocket message:', err);
         }
       };
       
       setSocket(newSocket);
       
       return () => {
         if (newSocket) {
           newSocket.close();
         }
       };
     }, [open]);
     
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
           
           {detailedStatus && (
             <div className="space-y-4">
               {/* Detailed status display */}
               {detailedStatus.import_jobs.length > 0 && (
                 <div>
                   <h3 className="font-medium mb-2">Import Jobs</h3>
                   <div className="space-y-3">
                     {detailedStatus.import_jobs.map(job => (
                       <div key={job.id} className="border rounded p-3">
                         <div className="flex justify-between mb-1">
                           <span className="font-medium">{job.slug}</span>
                           <span className="text-sm">{job.state}</span>
                         </div>
                         {job.total_rows && (
                           <>
                             <Progress value={job.progress_pct || 0} className="h-2 mb-1" />
                             <div className="text-xs text-right">
                               {job.imported_rows || 0} of {job.total_rows} rows ({job.progress_pct || 0}%)
                             </div>
                           </>
                         )}
                       </div>
                     ))}
                   </div>
                 </div>
               )}
               
               {detailedStatus.analytics_tasks.length > 0 && (
                 <div>
                   <h3 className="font-medium mb-2">Analytics Tasks</h3>
                   <div className="space-y-2">
                     {detailedStatus.analytics_tasks.map(task => (
                       <div key={task.id} className="border rounded p-2 flex justify-between">
                         <span>{task.command}</span>
                         <span className="text-sm">{task.state}</span>
                       </div>
                     ))}
                   </div>
                 </div>
               )}
               
               {detailedStatus.system_stable && (
                 <div className="text-center text-green-600 py-2">
                   All data processing complete
                 </div>
               )}
             </div>
           )}
         </DialogContent>
       </Dialog>
     );
   }
   ```

4. Add API route for detailed status:
   ```typescript
   // src/app/api/system-status-details/route.ts
   import { NextResponse } from 'next/server';
   import { createSupabaseSSRClient } from '@/utils/supabase/server';

   export async function GET() {
     const client = await createSupabaseSSRClient();
     
     // Get import jobs in progress
     const { data: importJobs } = await client
       .from('import_job')
       .select('*')
       .not('state', 'in', '("finished","rejected")')
       .order('priority');
     
     // Get analytics tasks in progress
     const { data: analyticsTasks } = await client.rpc('get_analytics_tasks_in_progress');
     
     return NextResponse.json({
       import_jobs: importJobs || [],
       analytics_tasks: analyticsTasks || [],
       system_stable: (importJobs?.length === 0 && analyticsTasks?.length === 0)
     });
   }
   ```

## Testing Plan

1. Unit tests for database functions:
   - Test `is_system_stable()` with various system states
   - Test notification triggers with simulated state changes

2. Integration tests for WebSocket server:
   - Test connection and message handling
   - Verify correct notification routing

3. Frontend component tests:
   - Test status indicator rendering
   - Test modal lazy loading behavior

## Deployment Considerations

1. Ensure WebSocket server is properly configured in production
2. Monitor WebSocket connection performance
3. Consider rate limiting for detailed status requests
4. Add appropriate error handling for all components
