"use client";

import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function ImportPage() {
  const router = useRouter();
  const [newJobs, setNewJobs] = useState<number[]>([]);
  
  useGuardedEffect(() => {
    let eventSource: EventSource | null = null;
    let reconnectTimer: NodeJS.Timeout | null = null;
    
    const connectSSE = () => {
      // Close existing connection if any
      if (eventSource) {
        eventSource.close();
      }
      
      // Connect to SSE endpoint to listen for new jobs (all INSERTs)
      eventSource = new EventSource('/api/sse/import-jobs?scope=updates_and_all_inserts');
      
      eventSource.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          
          // Handle connection established message
          if (data.type === 'connection_established') {
            console.log('SSE connection established:', data);
          }
          
          // Handle new job notifications (INSERT)
          if (data.verb === 'INSERT' && data.import_job?.id) {
            console.log('New import job detected:', data);
            const newJob = data.import_job;
            setNewJobs(prev => {
              // Only add if not already in the list
              if (!prev.includes(newJob.id)) {
                return [...prev, newJob.id];
              }
              return prev;
            });

            // If the job slug matches our pattern, we might want to redirect
            if (newJob.slug && (
                newJob.slug.startsWith('import_lu_') ||
                newJob.slug.startsWith('import_es_')
            )) {
              // Optional: redirect to the job details page
              // router.push(`/import/jobs/${newJob.id}`);
            }
          }
        } catch (error) {
          console.error('Error parsing SSE message:', error);
        }
      };
      
      // Handle heartbeat events
      eventSource.addEventListener('heartbeat', (event) => {
        try {
          const data = JSON.parse(event.data);
          console.log('SSE heartbeat received:', data.timestamp);
        } catch (error) {
          console.error('Error parsing heartbeat:', error);
        }
      });
      
      eventSource.onerror = (error) => {
        console.error('SSE connection error:', error);
        
        // Close the current connection
        if (eventSource) {
          eventSource.close();
          eventSource = null;
        }
        
        // Attempt to reconnect after a delay
        if (reconnectTimer) {
          clearTimeout(reconnectTimer);
        }
        
        reconnectTimer = setTimeout(() => {
          console.log('Attempting to reconnect SSE...');
          connectSSE();
        }, 5000); // Reconnect after 5 seconds
      };
    };
    
    // Initial connection
    connectSSE();
    
    // Cleanup function
    return () => {
      if (eventSource) {
        eventSource.close();
      }
      
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
      }
    };
  }, [router], 'ImportPage:sseConnector');
  
  return (
    <div className="space-y-6 text-center">
      <h1 className="text-center text-2xl">Welcome</h1>
      <p>
        In this onboarding guide we will try to help you get going with Statbus.
      </p>
      
      {newJobs.length > 0 && (
        <div className="p-4 bg-green-50 border border-green-200 rounded-md">
          <p className="font-medium text-green-800">
            {newJobs.length} new import job{newJobs.length > 1 ? 's' : ''} detected!
          </p>
          <Link className="text-green-600 underline" href="/import/jobs">
            View jobs
          </Link>
        </div>
      )}
      
      <Link className="block underline" href="/import/legal-units">
        Start
      </Link>
    </div>
  );
}
