"use server";

import { createSupabaseSSGClient as serverClient } from "@/utils/supabase/server";
import { SupabaseClient } from '@supabase/supabase-js';
import { Tables } from "@/lib/database.types";

export interface BaseData {
  statDefinitions: Tables<"stat_definition_ordered">[];
  externalIdentTypes: Tables<"external_ident_type_ordered">[];
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context">;
}

export async function getBaseData(): Promise<BaseData> {
  let client: SupabaseClient;
  try {
    client = await serverClient();
    if (!client || typeof client.from !== 'function') {
      throw new Error('Supabase client is not properly initialized.');
    }
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(`Failed to create Supabase client: ${error.message}`);
    } else {
      throw new Error('Failed to create Supabase client: An unknown error occurred.');
    }
  }

  let maybeStatDefinitions, maybeExternalIdentTypes, maybeTimeContexts;
  try {
    [
      { data: maybeStatDefinitions },
      { data: maybeExternalIdentTypes },
      { data: maybeTimeContexts },
    ] = await Promise.all([
      client.from("stat_definition_ordered").select(),
      client.from("external_ident_type_ordered").select(),
      client.from("time_context").select(),
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

  return {
    statDefinitions,
    externalIdentTypes,
    timeContexts,
    defaultTimeContext,
  };
}
