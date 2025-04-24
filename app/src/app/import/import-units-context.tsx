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

  // Set up SSE for job updates
  useEffect(() => {
    const jobId = job.currentJob?.id;
    if (!jobId) return;

    // Clean up existing connection
    if (eventSource) {
      eventSource.close();
    }

    // Create new connection
    const newEventSource = new EventSource(`/api/sse/import-jobs?ids=${jobId}`);
    
    newEventSource.onmessage = (event) => {
      try {
        if (event.data.trim() === '') return;
        
        setJob(prev => ({ ...prev, lastMessageTime: Date.now() }));
        const ssePayload = JSON.parse(event.data);
        
        if (ssePayload.type === "connection_established") return;
        
        if (ssePayload && typeof ssePayload === 'object' && ssePayload.id === jobId) {
          setJob(prev => ({
            ...prev,
            currentJob: prev.currentJob ? {
              ...prev.currentJob,
              ...ssePayload
            } : null
          }));
        }
      } catch (error) {
        console.error("Error parsing SSE message:", error);
      }
    };

    setEventSource(newEventSource);

    return () => {
      newEventSource.close();
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
