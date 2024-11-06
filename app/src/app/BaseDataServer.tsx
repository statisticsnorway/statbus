"use server";

import { SupabaseClient } from '@supabase/supabase-js';
import { Tables } from "@/lib/database.types";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { ClientBaseDataProvider } from "./BaseDataClient";

export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[];
  externalIdentTypes: Tables<"external_ident_type_active">[];
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context">;
  hasStatisticalUnits: boolean;
}

export async function getBaseData(client: SupabaseClient): Promise<BaseData> {

  if (!client || typeof client.from !== 'function') {
    throw new Error('Supabase client is not properly initialized.');
  }

  let maybeStatDefinitions, maybeExternalIdentTypes, maybeTimeContexts, maybeStatisticalUnit;
  try {
    [
      { data: maybeStatDefinitions },
      { data: maybeExternalIdentTypes },
      { data: maybeTimeContexts },
      { data: maybeStatisticalUnit },
    ] = await Promise.all([
      client.from("stat_definition_active").select(),
      client.from("external_ident_type_active").select(),
      client.from("time_context").select(),
      client.from("statistical_unit").select("*").limit(1),
    ]);
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(`Failed to create Supabase client: ${error.message}`);
    } else {
      throw new Error('Failed to create Supabase client: An unknown error occurred.');
    }
  }

  if (!maybeTimeContexts || maybeTimeContexts.length === 0) {
    throw new Error("Missing required time context");
  }
  const statDefinitions = maybeStatDefinitions as NonNullable<typeof maybeStatDefinitions>;
  const externalIdentTypes = maybeExternalIdentTypes as NonNullable<typeof maybeExternalIdentTypes>;
  const timeContexts = maybeTimeContexts as NonNullable<typeof maybeTimeContexts>;
  const defaultTimeContext = timeContexts[0];
  const hasStatisticalUnits = maybeStatisticalUnit !== null && maybeStatisticalUnit.length > 0;

  return {
    statDefinitions,
    externalIdentTypes,
    timeContexts,
    defaultTimeContext,
    hasStatisticalUnits,
  };
}

// Server component to fetch and provide base data
export const ServerBaseDataProvider = async ({ children }: { children: React.ReactNode }) => {
  const client = await createSupabaseSSRClient();
  const baseData = await getBaseData(client);

  return (
    <ClientBaseDataProvider initalBaseData={baseData}>
      {children}
    </ClientBaseDataProvider>
  );
};
