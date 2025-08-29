"use client";

/**
 * REST Client Atom
 *
 * This file contains the atom for managing the REST client instance.
 * It is isolated to prevent circular dependencies with other atom files
 * that might need access to the client.
 */

import { atom } from 'jotai'
import type { Database } from '@/lib/database.types'
import type { PostgrestClient } from '@supabase/postgrest-js'

// ============================================================================
// REST CLIENT ATOM - Replace RestClientStore
// ============================================================================

export const restClientAtom = atom<PostgrestClient<Database> | null>(null)
