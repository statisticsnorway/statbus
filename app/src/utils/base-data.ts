"use server";
import { createSupabaseServerClient as serverClient } from "@/utils/supabase/server";
import { SupabaseClient } from '@supabase/supabase-js';
import { Tables } from "@/lib/database.types";
//import { User } from "@supabase/auth-js/src/lib/types";

export interface BaseData {
  //activityCategories: Tables<"activity_category_used">[];
  //regions: Tables<"region_used">[];
  statDefinitions: Tables<"stat_definition_ordered">[];
  externalIdentTypes: Tables<"external_ident_type_ordered">[];
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context">;
  //isAuthenticated: boolean;
  //user: User | null;
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

  let maybeActivityCategories, maybeRegions, maybeStatDefinitions, maybeExternalIdentTypes, maybeTimeContexts, user;
  try {
    [
      //{ data: maybeActivityCategories },
      //{ data: maybeRegions },
      { data: maybeStatDefinitions },
      { data: maybeExternalIdentTypes },
      { data: maybeTimeContexts },
      //{ data: { user } }
    ] = await Promise.all([
      //client.from("activity_category_used").select(),
      //client.from("region_used").select(),
      client.from("stat_definition_ordered").select(),
      client.from("external_ident_type_ordered").select(),
      client.from("time_context").select(),
      //client.auth.getUser()
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
  //const activityCategories = maybeActivityCategories as NonNullable<typeof maybeActivityCategories>;
  //const regions = maybeRegions as NonNullable<typeof maybeRegions>;
  const statDefinitions = maybeStatDefinitions as NonNullable<typeof maybeStatDefinitions>;
  const externalIdentTypes = maybeExternalIdentTypes as NonNullable<typeof maybeExternalIdentTypes>;
  const timeContexts = maybeTimeContexts as NonNullable<typeof maybeTimeContexts>;
  const defaultTimeContext = timeContexts[0];
  //const isAuthenticated = user != null;

  return {
    //activityCategories,
    //regions,
    statDefinitions,
    externalIdentTypes,
    timeContexts,
    defaultTimeContext,
    //isAuthenticated,
    //user
  };
}
