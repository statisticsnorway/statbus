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

// Separate interfaces for better organization
interface UnitCounts {
  legalUnits: number | null;
  establishmentsWithLegalUnit: number | null;
  establishmentsWithoutLegalUnit: number | null;
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
  
  // Import job creation
  createImportJob: (definitionSlug: string) => Promise<ImportJob | null>;
}

const ImportUnitsContext = createContext<ImportUnitsContextType | undefined>(
  undefined
);

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

  const [client, setClient] = useState<StatbusClient | null>(null);

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

  // Simplified count refresh function
  const refreshUnitCount = useCallback(
    async (
      unitType:
        | "legalUnits"
        | "establishmentsWithLegalUnit"
        | "establishmentsWithoutLegalUnit"
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
      refreshUnitCount("legalUnits"),
      refreshUnitCount("establishmentsWithLegalUnit"),
      refreshUnitCount("establishmentsWithoutLegalUnit"),
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
    setTimeContext((prev) => ({ ...prev, useExplicitDates }));
  }, []);

  // Job creation - only creates the job, doesn't store it in context
  const createImportJob = useCallback(
    async (definitionSlug: string): Promise<ImportJob | null> => {
      if (!client) throw new Error("Client not initialized");
      if (!timeContext.selectedContext && !timeContext.useExplicitDates) {
        throw new Error("Either selectedContext or useExplicitDates must be set");
      }

      // Get definition ID
      const { data: definitionData, error: definitionError } = await client
        .from("import_definition")
        .select("id")
        .eq("slug", definitionSlug)
        .maybeSingle(); // Use maybeSingle to handle not found gracefully

      if (definitionError) {
        throw new Error(
          `Error fetching import definition: ${definitionError.message}`
        );
      }
      if (!definitionData) {
        throw new Error(`Import definition not found for slug: ${definitionSlug}`);
      }

      // Create job
      const insertData: any = {
        description: `Import job for ${definitionSlug}`,
        definition_id: definitionData.id,
      };

      if (!timeContext.useExplicitDates && timeContext.selectedContext) {
        insertData.default_valid_from = timeContext.selectedContext.valid_from;
        insertData.default_valid_to = timeContext.selectedContext.valid_to;
      }

      const { data, error } = await client
        .from("import_job")
        .insert(insertData)
        .select("*");
      
      if (error) {
        throw new Error(`Error creating import job: ${error.message}`);
      }
      
      // Ensure data is not null and has at least one element
      if (!data || data.length === 0) {
        throw new Error("No data returned after creating import job");
      }
      
      const job = data[0] as ImportJob;

      // Return the newly created job, but don't store it in context state
      return job;
    },
    [client, timeContext.selectedContext, timeContext.useExplicitDates]
  );

  // Memoize the context value to prevent unnecessary re-renders of consumers
  const contextValue: ImportUnitsContextType = React.useMemo(
    () => ({
      counts,
      refreshCounts,
      refreshUnitCount,

      timeContext: {
        availableContexts: timeContext.availableContexts,
        selectedContext: timeContext.selectedContext,
        useExplicitDates: timeContext.useExplicitDates,
      },
      setSelectedTimeContext,
      setUseExplicitDates,

      createImportJob,
      // List all state values and memoized callbacks as dependencies for useMemo
    }),
    [
      counts,
      refreshCounts,
      refreshUnitCount,
      timeContext.availableContexts,
      timeContext.selectedContext,
      timeContext.useExplicitDates,
      setSelectedTimeContext,
      setUseExplicitDates,
      createImportJob,
    ]
  );

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
