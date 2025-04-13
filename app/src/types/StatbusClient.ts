/**
 * StatbusClient type definition
 */

import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';

// Type for a Statbus client
export type StatbusClient = PostgrestClient<Database>;
