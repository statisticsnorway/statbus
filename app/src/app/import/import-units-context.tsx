"use client";
import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
} from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { PostgrestClient } from '@supabase/postgrest-js';
import { Database, Tables } from '@/lib/database.types';
import { useBaseData } from "@/app/BaseDataClient";

// Define types
type StatbusClient = PostgrestClient<Database>;
type TimeContext = Tables<"time_context">;
type ImportJob = Tables<"import_job">;
type ImportDefinition = Tables<"import_definition">;

// Separate interfaces for better organization
interface UnitCounts {
  legalUnits: number | null;
  establishmentsWithLegalUnit: number | null;
  establishmentsWithoutLegalUnit: number | null;
}

interface ImportJobState {
  currentJob: ImportJob | null;
  currentDefinition: ImportDefinition | null;
  lastMessageTime: number;
}

interface TimeContextState {
  availableContexts: TimeContext[];
  selectedContext: TimeContext | null;
  useExplicitDates: boolean;
}

interface ImportUnitsContextType {
  // Unit counts
  counts: UnitCounts;
  refreshCounts: () => Promise<void>;
  refreshUnitCount: (unitType: 'legalUnits' | 'establishmentsWithLegalUnit' | 'establishmentsWithoutLegalUnit') => Promise<void>;
  
  // Time context
  timeContext: TimeContextState;
  setSelectedTimeContext: (timeContextIdent: string | null) => void;
  setUseExplicitDates: (useExplicitDates: boolean) => void;
  
  // Import job
  job: ImportJobState;
  createImportJob: (definitionSlug: string) => Promise<ImportJob | null>;
  getImportJobBySlug: (slug: string) => Promise<ImportJob | null>;
  refreshImportJob: () => Promise<void>;
}

const ImportUnitsContext = createContext<ImportUnitsContextType | undefined>(undefined);

export const ImportUnitsProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  // Get base data context
  const { timeContexts: baseTimeContexts, defaultTimeContext: baseDefaultTimeContext } = useBaseData();

  // Split state into logical groups
  const [counts, setCounts] = useState<UnitCounts>({
    legalUnits: null,
    establishmentsWithLegalUnit: null,
    establishmentsWithoutLegalUnit: null,
  });
  
  const [timeContext, setTimeContext] = useState<TimeContextState>({
    availableContexts: [],
    selectedContext: null,
    useExplicitDates: false,
  });
  
  const [job, setJob] = useState<ImportJobState>({
    currentJob: null,
    currentDefinition: null,
    lastMessageTime: 0,
  });

  const [client, setClient] = useState<StatbusClient | null>(null);
  const [eventSource, setEventSource] = useState<EventSource | null>(null);

  // Initialize client
  useEffect(() => {
    getBrowserRestClient().then(postgrestClient => {
      if (!postgrestClient) throw new Error("Failed to get browser REST client");
      setClient(postgrestClient);
    });
  }, []);

  // Sync time contexts from BaseData
  useEffect(() => {
    if (baseTimeContexts) {
      const inputContexts = baseTimeContexts.filter(
        tc => tc.scope === "input" || tc.scope === "input_and_query"
      );
      
      setTimeContext(prev => ({
        ...prev,
        availableContexts: inputContexts,
        selectedContext: prev.selectedContext || baseDefaultTimeContext || 
          (inputContexts.length > 0 ? inputContexts[0] : null)
      }));
    }
  }, [baseTimeContexts, baseDefaultTimeContext]);

  // Store the current job ID in a ref to avoid dependency cycles
  const currentJobIdRef = React.useRef<number | null>(null);
  
  // Set up SSE for job updates
  useEffect(() => {
    const jobId = job.currentJob?.id;
     
    // Update the ref
    currentJobIdRef.current = jobId ?? null; // Convert undefined to null
     
    // Skip if no job ID
    if (!jobId) {
      return;
    }

    // Don't recreate if we already have a connection for this job
    if (eventSource && eventSource.url.includes(`?ids=${jobId}`)) {
      return;
    }
    
    // Clean up existing connection
    if (eventSource) {
      eventSource.close();
      setEventSource(null);
    }

    // Create new connection
    console.log(`Creating SSE connection for job ${jobId}`);
    const newEventSource = new EventSource(`/api/sse/import-jobs?ids=${jobId}`);
    
    // Add specific handler for heartbeat events
    newEventSource.addEventListener("heartbeat", (event) => {
      // Just log heartbeat at debug level if needed
      // console.debug("Heartbeat received:", event.data);
    });
    
    newEventSource.onmessage = (event) => {
      try {
        if (event.data.trim() === '') return;
        
        // Update last message time
        setJob(prev => ({ ...prev, lastMessageTime: Date.now() }));
        
        // Parse the payload
        const ssePayload = JSON.parse(event.data);
        
        // Skip connection established messages
        if (ssePayload.type === "connection_established") return;
        
        // Skip heartbeat messages (these should be handled by the heartbeat event listener)
        if (ssePayload.type === "heartbeat") return;
        
        // Validate the basic structure { verb: '...', import_job: { ... } }
        if (!ssePayload || typeof ssePayload !== 'object' || !ssePayload.verb || !ssePayload.import_job) {
          console.error("Invalid SSE payload structure in context (expected import_job key):", ssePayload);
          return;
        }

        const verb = ssePayload.verb as 'INSERT' | 'UPDATE' | 'DELETE';
        const jobData = ssePayload.import_job; // Use the 'import_job' key

        // Get the current job ID from the ref to avoid closure issues
        const currentId = currentJobIdRef.current;

        // Skip if no current job ID
        if (!currentId) return;

        // Handle DELETE verb
        if (verb === "DELETE" && jobData.id === currentId) {
          console.log("Job was deleted (context):", currentId);
          setJob(prev => ({
            ...prev,
            currentJob: null,
            currentDefinition: null
          }));
          return;
        }

        // Handle UPDATE/INSERT verbs - jobData should be the ImportJob object
        if ((verb === 'UPDATE' || verb === 'INSERT') && jobData.id === currentId) {
          console.log(`Received ${verb} event for job ${currentId} (context)`);

          // jobData is the clean job data already
          const updatedJobData = jobData as ImportJob;

          setJob(prev => ({
            ...prev,
            currentJob: prev.currentJob ? {
              ...prev.currentJob, // Keep existing fields
              ...updatedJobData   // Overwrite with new data
            } : null // Should not happen if currentId is set, but handle defensively
          }));
        }
      } catch (error) {
        console.error("Error parsing SSE message:", error);
      }
    };

    // Add error handling with exponential backoff
    let reconnectAttempt = 0;
    const maxReconnectDelay = 30000; // 30 seconds max
    let reconnectTimeout: NodeJS.Timeout | null = null;
    
    newEventSource.onerror = (error) => {
      console.error("SSE connection error in import context:", error);
      
      // Only close if not already closed
      if (newEventSource.readyState !== 2) { // 2 = CLOSED
        newEventSource.close();
      }
      
      // Don't reconnect if the component is unmounting or the job ID has changed
      if (currentJobIdRef.current !== jobId) {
        console.log("Job ID changed, not reconnecting");
        return;
      }
      
      // Calculate backoff delay with exponential increase and jitter
      reconnectAttempt++;
      const baseDelay = Math.min(1000 * Math.pow(1.5, reconnectAttempt), maxReconnectDelay);
      const jitter = Math.random() * 0.3 * baseDelay; // Add up to 30% jitter
      const reconnectDelay = Math.floor(baseDelay + jitter);
      
      console.log(`Attempting to reconnect import context SSE in ${reconnectDelay}ms (attempt ${reconnectAttempt})`);
      
      // Clear any existing timeout
      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }
      
      // Attempt to reconnect after calculated delay
      reconnectTimeout = setTimeout(() => {
        console.log("Reconnecting import context SSE now...");
        reconnectTimeout = null;
        setEventSource(null);
      }, reconnectDelay);
    };

    setEventSource(newEventSource);

    return () => {
      console.log(`Closing SSE connection for job ${jobId}`);
      newEventSource.close();
      setEventSource(null);
      
      // Clear any pending reconnect timeout
      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }
    };
  }, [job.currentJob?.id]);

  // Simplified count refresh function
  const refreshUnitCount = useCallback(async (
    unitType: 'legalUnits' | 'establishmentsWithLegalUnit' | 'establishmentsWithoutLegalUnit'
  ) => {
    if (!client) throw new Error("Client not initialized");

    let query;
    switch (unitType) {
      case 'legalUnits':
        query = client.from("legal_unit").select("*", { count: "exact" }).limit(0);
        break;
      case 'establishmentsWithLegalUnit':
        query = client.from("establishment").select("*", { count: "exact" })
          .not("legal_unit_id", "is", null).limit(0);
        break;
      case 'establishmentsWithoutLegalUnit':
        query = client.from("establishment").select("*", { count: "exact" })
          .is("legal_unit_id", null).limit(0);
        break;
    }

    const { count } = await query;
    setCounts(prev => ({ ...prev, [unitType]: count }));
  }, [client]);

  // Refresh all counts at once
  const refreshCounts = useCallback(async () => {
    if (!client) throw new Error("Client not initialized");
    
    await Promise.all([
      refreshUnitCount('legalUnits'),
      refreshUnitCount('establishmentsWithLegalUnit'),
      refreshUnitCount('establishmentsWithoutLegalUnit')
    ]);
  }, [client, refreshUnitCount]);

  // Load counts when client is ready
  useEffect(() => {
    if (client) {
      refreshCounts();
    }
  }, [client, refreshCounts]);

  // Time context management
  const setSelectedTimeContext = useCallback((timeContextIdent: string | null) => {
    setTimeContext(prev => ({
      ...prev,
      selectedContext: prev.availableContexts.find(tc => tc.ident === timeContextIdent) || null
    }));
  }, []);

  const setUseExplicitDates = useCallback((useExplicitDates: boolean) => {
    setTimeContext(prev => ({ ...prev, useExplicitDates }));
  }, []);

  // Job management
  const createImportJob = useCallback(async (definitionSlug: string): Promise<ImportJob | null> => {
    if (!client) throw new Error("Client not initialized");
    if (!timeContext.selectedContext && !timeContext.useExplicitDates) {
      throw new Error("Either selectedContext or useExplicitDates must be set");
    }

    // Generate job slug
    const timestamp = new Date().getTime();
    const jobSlug = `${definitionSlug}_${timestamp}`;
    
    // Get definition ID
    const { data: definitionData, error: definitionError } = await client
      .from("import_definition")
      .select("id")
      .eq("slug", definitionSlug)
      .single();
      
    if (definitionError || !definitionData) {
      throw new Error(`Error fetching import definition: ${definitionError?.message || "Definition not found"}`);
    }
    
    // Create job
    const insertData: any = {
      slug: jobSlug,
      description: `Import job for ${definitionSlug}`,
      definition_id: definitionData.id
    };

    if (!timeContext.useExplicitDates && timeContext.selectedContext) {
      insertData.default_valid_from = timeContext.selectedContext.valid_from;
      insertData.default_valid_to = timeContext.selectedContext.valid_to;
    }

    const { data, error } = await client
      .from("import_job")
      .insert(insertData)
      .select("*")
      .single();

    if (error || !data) {
      throw new Error(`Error creating import job: ${error?.message || "No data returned"}`);
    }

    const newJob: ImportJob = data;
    setJob(prev => ({ ...prev, currentJob: newJob }));
    return newJob;
  }, [client, timeContext.selectedContext, timeContext.useExplicitDates]);

  const getImportJobBySlug = useCallback(async (slug: string): Promise<ImportJob | null> => {
    if (!slug) throw new Error("No slug provided");
    
    // Return cached job if available
    if (job.currentJob?.slug === slug) {
      return job.currentJob;
    }
    
    // Get client if needed
    const postgrestClient = client || await getBrowserRestClient();
    if (!postgrestClient) throw new Error("Failed to initialize REST client");
    
    if (!client) setClient(postgrestClient);
    
    // Fetch job and definition in parallel
    const { data, error } = await postgrestClient
      .from("import_job")
      .select("*")
      .eq("slug", slug)
      .single();

    if (error) throw new Error(`Error fetching import job: ${error.message}`);
    if (!data) throw new Error(`No data returned for import job with slug ${slug}`);

    const fetchedJob: ImportJob = data;
    
    // Fetch the associated import definition if needed
    if (fetchedJob.definition_id) {
      const { data: definitionData, error: definitionError } = await postgrestClient
        .from("import_definition")
        .select("*")
        .eq("id", fetchedJob.definition_id)
        .single();
        
      if (!definitionError && definitionData) {
        setJob(prev => ({ 
          ...prev, 
          currentJob: fetchedJob,
          currentDefinition: definitionData
        }));
      } else {
        console.error(`Error fetching import definition: ${definitionError?.message}`);
        setJob(prev => ({ ...prev, currentJob: fetchedJob }));
      }
    } else {
      setJob(prev => ({ ...prev, currentJob: fetchedJob }));
    }
    
    return fetchedJob;
  }, [client, job.currentJob]);

  const refreshImportJob = useCallback(async () => {
    if (!job.currentJob?.id) throw new Error("No current import job");
    
    // Skip if recent SSE update
    if (Date.now() - job.lastMessageTime < 5000) return;

    const postgrestClient = client || await getBrowserRestClient();
    if (!postgrestClient) throw new Error("Failed to initialize REST client");

    const { data, error } = await postgrestClient
      .from("import_job")
      .select("*")
      .eq("id", job.currentJob.id)
      .single();

    if (error) throw new Error(`Error refreshing import job: ${error.message}`);
    if (!data) throw new Error(`Import job with ID ${job.currentJob.id} not found`);

    setJob(prev => ({ ...prev, currentJob: data, lastMessageTime: Date.now() }));
    
    // Also refresh the import definition if needed
    if (data.definition_id && (!job.currentDefinition || job.currentDefinition.id !== data.definition_id)) {
      const { data: definitionData, error: definitionError } = await postgrestClient
        .from("import_definition")
        .select("*")
        .eq("id", data.definition_id)
        .single();
        
      if (!definitionError && definitionData) {
        setJob(prev => ({ ...prev, currentDefinition: definitionData }));
      }
    }
  }, [client, job.currentJob, job.currentDefinition, job.lastMessageTime]);

  // Create context value with the new structure
  const contextValue: ImportUnitsContextType = {
    counts,
    refreshCounts,
    refreshUnitCount,
    
    timeContext: {
      availableContexts: timeContext.availableContexts,
      selectedContext: timeContext.selectedContext,
      useExplicitDates: timeContext.useExplicitDates
    },
    setSelectedTimeContext,
    setUseExplicitDates,
    
    job: {
      currentJob: job.currentJob,
      currentDefinition: job.currentDefinition,
      lastMessageTime: job.lastMessageTime
    },
    createImportJob,
    getImportJobBySlug,
    refreshImportJob,
  };

  return (
    <ImportUnitsContext.Provider value={contextValue}>
      {children}
    </ImportUnitsContext.Provider>
  );
};

// Simple hook to access the context
export const useImportUnits = () => {
  const context = useContext(ImportUnitsContext);
  if (!context) {
    throw new Error("useImportUnits must be used within a ImportUnitsProvider");
  }
  return context;
};
