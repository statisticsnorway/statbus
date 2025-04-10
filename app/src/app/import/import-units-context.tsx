"use client";
import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
} from "react";
import { createPostgRESTBrowserClient } from "@/utils/auth/postgrest-client-browser";
import { SupabaseClient } from "@supabase/supabase-js";

interface ImportUnitsState {
  numberOfLegalUnits: number | null;
  numberOfEstablishmentsWithLegalUnit: number | null;
  numberOfEstablishmentsWithoutLegalUnit: number | null;
}

interface ImportUnitsContextType extends ImportUnitsState {
  refreshCounts: () => Promise<void>;
  refreshNumberOfLegalUnits: () => Promise<void>;
  refreshNumberOfEstablishmentsWithLegalUnit: () => Promise<void>;
  refreshNumberOfEstablishmentsWithoutLegalUnit: () => Promise<void>;
}

const ImportUnitsContext = createContext<ImportUnitsContextType | undefined>(
  undefined
);

export const ImportUnitsProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [state, setState] = useState<ImportUnitsState>({
    numberOfLegalUnits: null,
    numberOfEstablishmentsWithLegalUnit: null,
    numberOfEstablishmentsWithoutLegalUnit: null,
  });

  const [client, setClient] = useState<SupabaseClient | null>(null);

  const refreshNumberOfLegalUnits = useCallback(async () => {
    if (!client) return;

    const { count: numberOfLegalUnits } = await client
      .from("legal_unit")
      .select("*", { count: "exact" })
      .limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfLegalUnits,
    }));
  }, [client]);

  const refreshNumberOfEstablishmentsWithLegalUnit = useCallback(async () => {
    if (!client) return;

    const { count: numberOfEstablishmentsWithLegalUnit } = await client
      .from("establishment")
      .select("*", { count: "exact" })
      .not("legal_unit_id", "is", null)
      .limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfEstablishmentsWithLegalUnit,
    }));
  }, [client]);
  const refreshNumberOfEstablishmentsWithoutLegalUnit =
    useCallback(async () => {
      if (!client) return;

      const { count: numberOfEstablishmentsWithoutLegalUnit } = await client
        .from("establishment")
        .select("*", { count: "exact" })
        .is("legal_unit_id", null)
        .limit(0);

      setState((prevState) => ({
        ...prevState,
        numberOfEstablishmentsWithoutLegalUnit,
      }));
    }, [client]);

  const refreshCounts = useCallback(async () => {
    await refreshNumberOfLegalUnits();
    await refreshNumberOfEstablishmentsWithLegalUnit();
    await refreshNumberOfEstablishmentsWithoutLegalUnit();
  }, [
    refreshNumberOfEstablishmentsWithLegalUnit,
    refreshNumberOfEstablishmentsWithoutLegalUnit,
    refreshNumberOfLegalUnits,
  ]);

  useEffect(() => {
    const initializeClient = async () => {
      const supabaseClient = await createPostgRESTBrowserClient();
      setClient(supabaseClient);
    };
    initializeClient();
  }, []);

  useEffect(() => {
    if (client) {
      refreshCounts();
    }
  }, [client, refreshCounts]);

  return (
    <ImportUnitsContext.Provider
      value={{
        ...state,
        refreshCounts,
        refreshNumberOfLegalUnits,
        refreshNumberOfEstablishmentsWithLegalUnit,
        refreshNumberOfEstablishmentsWithoutLegalUnit,
      }}
    >
      {children}
    </ImportUnitsContext.Provider>
  );
};

export const useImportUnits = () => {
  const context = useContext(ImportUnitsContext);
  if (!context) {
    throw new Error("useImportUnits must be used within a ImportUnitsProvider");
  }
  return context;
};
