/**
 * db-listener.ts - Singleton for managing a persistent PostgreSQL connection
 * to listen for notifications (pg_notify) on the 'check' channel.
 *
 * This module ensures only one listener connection is active per server process
 * and distributes notifications to subscribed SSE clients via callbacks.
 */

import { Client } from 'pg';
import { Tables, type Database } from '@/lib/database.types';
import { type ImportJobWithDetails } from '@/atoms/import';

// Extend the global NodeJS namespace to declare our custom properties
// This helps persist state across hot module reloads in development
declare global {
  // eslint-disable-next-line no-var
  var __dbListenerCallbacks: Map<string, Set<NotificationCallback>> | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerClient: Client | null | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerConnecting: boolean | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerReconnectTimeout: NodeJS.Timeout | null | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerDebounceTimers: { [key: string]: NodeJS.Timeout } | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerReconnectDelay: number | undefined;
}

/**
 * Helper function to get a required environment variable or throw an error.
 * @param varName The name of the environment variable.
 * @returns The value of the environment variable.
 * @throws Error if the environment variable is not set or is empty.
 */
function getRequiredEnvVar(varName: string): string {
  const value = process.env[varName];
  if (!value) {
    throw new Error(`Missing required environment variable: ${varName}`);
  }
  return value;
}

/**
 * Gets database connection parameters, handling both Docker and local development environments.
 * Ensures required environment variables are set.
 */
export function getDbHostPort() {
  // Use helper for required variables to ensure they exist and narrow types
  const dbName = getRequiredEnvVar('POSTGRES_APP_DB'); // Use the app-specific DB
  const dbUser = getRequiredEnvVar('POSTGRES_NOTIFY_USER');
  // Password might be optional in some environments (e.g., local dev with trust auth)
  const dbPassword = process.env.POSTGRES_NOTIFY_PASSWORD || ''; // Default to empty string if not set

  let dbHost: string;
  let dbPort: number; // Changed type to number

  // Helper to parse port string to number
  const parsePort = (portStr: string | undefined, varName: string): number => {
    if (!portStr) {
      throw new Error(`Missing required environment variable: ${varName}`);
    }
    const portNum = parseInt(portStr, 10);
    if (isNaN(portNum) || portNum <= 0 || portNum > 65535) {
      throw new Error(`Invalid port number configured for ${varName}: ${portStr}`);
    }
    return portNum;
  };

  // Check if CADDY_DB_PORT is set for local development override
  const localPortStr = process.env.CADDY_DB_PORT;
  if (localPortStr) {
    // Validate localPortStr format before parsing
    if (!/^\d+$/.test(localPortStr)) {
       throw new Error(`Invalid format for environment variable CADDY_DB_PORT: ${localPortStr}. Must be a number.`);
    }
    dbHost = 'localhost';
    dbPort = parsePort(localPortStr, 'CADDY_DB_PORT');
  } else {
    // Default to Docker internal host/port, use helper to ensure they exist
    dbHost = getRequiredEnvVar('POSTGRES_HOST');
    const portStr = getRequiredEnvVar('POSTGRES_PORT');
    dbPort = parsePort(portStr, 'POSTGRES_PORT');
  }

  // The checks for dbName and dbUser are now handled by getRequiredEnvVar above.
  // The check for dbPassword remains lenient.

  return { dbName, dbUser, dbPassword, dbHost, dbPort };
}

// Define specific payload types for each channel
export type ImportJobProgressPayload = {
  type: 'import_job_progress';
  job_id: number;
  state: string;
  total_rows: number | null;
  analysis_completed_pct: number;
  imported_rows: number;
  import_completed_pct: number;
};

export type WorkerStatusPayload =
  | { type: string; status: boolean }
  | { type: 'pipeline_progress'; phases: Array<{ phase: string; step: string | null; total: number; completed: number; affected_establishment_count: number | null; affected_legal_unit_count: number | null; affected_enterprise_count: number | null }> }
  | ImportJobProgressPayload;

// Minimal payload from pg_notify
export type MinimalImportJobNotificationPayload = {
  verb: 'INSERT' | 'UPDATE' | 'DELETE';
  id: number;
};

// Enriched payload sent to the client, using a discriminated union for type safety
export type EnrichedImportJobNotificationPayload =
  | {
      verb: 'INSERT' | 'UPDATE';
      import_job: ImportJobWithDetails;
    }
  | {
      verb: 'DELETE';
      import_job: { id: number };
    };

// Create a discriminated union based on the channel
export type NotificationData =
  | { channel: 'worker_status'; payload: WorkerStatusPayload }
  | { channel: 'import_job'; payload: EnrichedImportJobNotificationPayload };

// Type for the callback function provided by SSE route handlers
export type NotificationCallback = (data: NotificationData) => void;

// Define the shape of our channel-based subscription store
type ChannelSubscribers = Map<string, Set<NotificationCallback>>;

// Use globalThis for broader compatibility and type safety with declared globals
const channelCallbacks: ChannelSubscribers = globalThis.__dbListenerCallbacks || new Map();
if (typeof globalThis !== 'undefined') {
  globalThis.__dbListenerCallbacks = channelCallbacks;
}

let pgClient: Client | null = globalThis.__dbListenerClient || null;
let isConnecting: boolean = globalThis.__dbListenerConnecting || false;
let reconnectTimeout: NodeJS.Timeout | null = globalThis.__dbListenerReconnectTimeout || null;

// Reconnection logic with exponential backoff
const INITIAL_RECONNECT_DELAY_MS = 1000;
const MAX_RECONNECT_DELAY_MS = 30000;
const RECONNECT_BACKOFF_FACTOR = 2;
let reconnectDelay: number = globalThis.__dbListenerReconnectDelay || INITIAL_RECONNECT_DELAY_MS;

// State for debouncing notifications
const debounceTimers: { [key: string]: NodeJS.Timeout } = globalThis.__dbListenerDebounceTimers || {};
if (typeof globalThis !== 'undefined') {
  globalThis.__dbListenerDebounceTimers = debounceTimers;
}
const DEBOUNCE_DELAY_MS = 500;

function handleWorkerStatusNotification(payload: WorkerStatusPayload) {
  // Clear any pending timer for this status type
  if (debounceTimers[payload.type]) {
    clearTimeout(debounceTimers[payload.type]);
  }

  // Set a new timer. If another notification for the same type arrives
  // before the timer fires, it will be cleared and replaced.
  debounceTimers[payload.type] = setTimeout(() => {
    const data: NotificationData = {
      channel: 'worker_status',
      payload: payload,
    };
    // Dispatch only to subscribers of the 'worker_status' channel
    channelCallbacks.get('worker_status')?.forEach(callback => callback(data));
    delete debounceTimers[payload.type]; // Clean up timer
  }, DEBOUNCE_DELAY_MS);
}

function handleImportJobProgressNotification(rawPayload: Record<string, unknown>) {
  const payload: ImportJobProgressPayload = {
    type: 'import_job_progress',
    job_id: rawPayload.job_id as number,
    state: rawPayload.state as string,
    total_rows: rawPayload.total_rows as number | null,
    analysis_completed_pct: rawPayload.analysis_completed_pct as number,
    imported_rows: rawPayload.imported_rows as number,
    import_completed_pct: rawPayload.import_completed_pct as number,
  };

  // Debounce per job_id to avoid flooding during rapid progress updates
  const debounceKey = `import_job_progress_${payload.job_id}`;
  if (debounceTimers[debounceKey]) {
    clearTimeout(debounceTimers[debounceKey]);
  }

  debounceTimers[debounceKey] = setTimeout(() => {
    const data: NotificationData = {
      channel: 'worker_status',
      payload,
    };
    channelCallbacks.get('worker_status')?.forEach(callback => callback(data));
    delete debounceTimers[debounceKey];
  }, DEBOUNCE_DELAY_MS);
}

// Update global references when these variables change
function updateGlobalClient(client: Client | null) {
  globalThis.__dbListenerClient = client;
  pgClient = client; // Update local variable as well
  return client;
}

function updateGlobalConnecting(connecting: boolean) {
  globalThis.__dbListenerConnecting = connecting;
  isConnecting = connecting; // Update local variable
  return connecting;
}

function updateGlobalReconnectTimeout(timeout: NodeJS.Timeout | null) {
  globalThis.__dbListenerReconnectTimeout = timeout;
  reconnectTimeout = timeout; // Update local variable
  return timeout;
}

function updateGlobalReconnectDelay(delay: number) {
  globalThis.__dbListenerReconnectDelay = delay;
  reconnectDelay = delay; // Update local variable
  return delay;
}


async function connectAndListen() {
  // Use local variables which are synced with globalThis
  // Check if the client object exists and is potentially connected/connecting
  if (pgClient) {
    return; // Already connected or connection attempt in progress
  }

  if (isConnecting) {
    return; // Connection attempt already in progress
  }

  updateGlobalConnecting(true); // Set connecting flag

  // Clear any pending reconnect timeout
  if (reconnectTimeout) {
    clearTimeout(reconnectTimeout);
    updateGlobalReconnectTimeout(null);
  }

  let dbHost: string | undefined;
  let dbPort: number | undefined;

  try {
    // Get database connection details
    const { dbName, dbUser, dbPassword, dbHost: host, dbPort: port } = getDbHostPort();
    dbHost = host;
    dbPort = port;

    const connectionString = `postgresql://${encodeURIComponent(dbUser)}:${encodeURIComponent(dbPassword)}@${dbHost}:${dbPort}/${encodeURIComponent(dbName)}`;
    // We'll skip this log and only show the connected message

    const newClient = new Client({
      connectionString: connectionString,
      application_name: 'statbus-app',
      // Add SSL configuration if needed for production
      // ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : undefined,
    });
    
    updateGlobalClient(newClient);

    newClient.on('notification', (msg) => {
      if (!msg.payload) return;
      
      if (msg.channel === 'worker_status') {
        try {
          const payload: WorkerStatusPayload = JSON.parse(msg.payload);
          handleWorkerStatusNotification(payload);
          if (process.env.NODE_ENV === 'development') {
             console.log(`DB Listener: Received worker_status notification:`, payload);
          }
        } catch (e) {
          console.error({ error: e, payload: msg.payload }, "DB Listener: Error parsing worker_status notification");
        }
      } else if (msg.channel === 'import_job_progress') {
        try {
          const payload = JSON.parse(msg.payload);
          handleImportJobProgressNotification(payload);
        } catch (e) {
          console.error({ error: e, payload: msg.payload }, "DB Listener: Error parsing import_job_progress notification");
        }
      } else if (msg.channel === 'import_job') {
        // Asynchronously handle enrichment
        handleImportJobNotification(msg.payload);
      }
    });

    newClient.on('error', (err) => {
      console.error({ error: err, dbHost, dbPort }, 'DB Listener: Connection error');
      // Connection might be lost, attempt reconnection
      closeConnectionAndScheduleReconnect();
    });

    newClient.on('end', () => {
      console.warn('DB Listener: Connection ended.');
      // Connection ended unexpectedly, attempt reconnection
      closeConnectionAndScheduleReconnect();
    });

    await newClient.connect();
    await newClient.query('LISTEN "worker_status";');
    await newClient.query('LISTEN "import_job";');
    await newClient.query('LISTEN "import_job_progress";');
    updateGlobalConnecting(false);
    console.log(`DB Listener: Connected to ${dbHost}:${dbPort}/${dbName} as ${dbUser} and listening on "worker_status", "import_job", and "import_job_progress" channels`);

    // On successful connection, reset the reconnect delay
    updateGlobalReconnectDelay(INITIAL_RECONNECT_DELAY_MS);

  } catch (error) {
    updateGlobalConnecting(false);
    console.error({ error, dbHost, dbPort }, 'DB Listener: Failed to connect or listen');
    updateGlobalClient(null); // Ensure client is null on failure
    scheduleReconnect(); // Schedule a retry
  }
}

function scheduleReconnect() {
  // Use local variable synced with globalThis
  if (!reconnectTimeout) {
    const timeout = setTimeout(() => {
      updateGlobalReconnectTimeout(null); // Clear the timeout ID before attempting connection
      connectAndListen(); // Attempt to reconnect
    }, reconnectDelay);
    
    updateGlobalReconnectTimeout(timeout);
    console.log(`DB Listener: Reconnection scheduled in ${reconnectDelay / 1000} seconds`);

    // Increase delay for next time, up to a max
    const nextDelay = Math.min(reconnectDelay * RECONNECT_BACKOFF_FACTOR, MAX_RECONNECT_DELAY_MS);
    updateGlobalReconnectDelay(nextDelay);
  }
}

async function handleImportJobNotification(payload: string) {
  try {
    const minimalPayload = JSON.parse(payload) as MinimalImportJobNotificationPayload;
    const { verb, id } = minimalPayload;

    let enrichedPayload: EnrichedImportJobNotificationPayload;

    if (verb === 'DELETE') {
      // For DELETE, we just forward the ID as there's nothing to fetch.
      enrichedPayload = {
        verb: 'DELETE',
        import_job: { id: id },
      };
    } else {
      // For INSERT or UPDATE, fetch the full job details using our raw pg client.
      // This runs outside a user request context, so we can't use PostgREST clients
      // that depend on request headers. We use the listener's own DB connection.
      if (!pgClient) {
        console.error('DB Listener: pgClient is not available for enriching import_job notification.');
        return;
      }

      if (process.env.NODE_ENV === 'development') {
        console.log(`DB Listener: Enriching notification for job ${id} using raw pgClient.`);
      }

      // This query constructs a JSON object that matches the structure expected by the client.
      // It uses to_jsonb(ij.*) to serialize the entire import_job row and merges it with
      // a manually constructed JSON object for the nested import_definition.
      const query = {
        text: `
          SELECT
            to_jsonb(ij.*) || jsonb_build_object(
              'import_definition', jsonb_build_object(
                'slug', idf.slug,
                'name', idf.name,
                'mode', idf.mode,
                'custom', idf.custom
              )
            ) AS job_data
          FROM public.import_job AS ij
          LEFT JOIN public.import_definition AS idf ON ij.definition_id = idf.id
          WHERE ij.id = $1
        `,
        values: [id],
      };

      const { rows } = await pgClient.query(query);

      if (rows.length === 0) {
        console.warn(`DB Listener: No import_job found for id ${id} during enrichment. It may have been deleted.`);
        return;
      }

      const jobData = rows[0].job_data;

      enrichedPayload = {
        verb,
        import_job: jobData as ImportJobWithDetails,
      };
    }
    
    // Distribute the enriched payload to all clients subscribed to this channel.
    const callbacksToNotify = channelCallbacks.get('import_job');
    if (callbacksToNotify) {
      callbacksToNotify.forEach(callback => {
        callback({
          channel: 'import_job',
          payload: enrichedPayload,
        });
      });
    }

    if (process.env.NODE_ENV === 'development') {
      console.log(`DB Listener: Enriched and sent import_job notification for job ${id} (verb: ${verb})`);
    }

  } catch (e) {
    console.error({ error: e, payload: payload }, "DB Listener: Error processing or enriching import_job notification");
  }
}

function closeConnectionAndScheduleReconnect() {
  // Use local variable synced with globalThis
  if (pgClient) {
    pgClient.end().catch((err: Error) => console.error({ error: err }, 'DB Listener: Error during connection end')); // Add type annotation
    updateGlobalClient(null);
    console.log('DB Listener: Connection closed, scheduling reconnect');
  }
  updateGlobalConnecting(false); // Ensure we allow a new connection attempt
  scheduleReconnect();
}

// --- Public API ---

/**
 * Adds a callback function to be invoked when a notification is received on a specific channel.
 * @param channel The channel to subscribe to.
 * @param callback Function to call with the notification data.
 */
export function addClientCallback(channel: string, callback: NotificationCallback) {
  if (!channelCallbacks.has(channel)) {
    channelCallbacks.set(channel, new Set());
  }
  channelCallbacks.get(channel)!.add(callback);
}

/**
 * Removes a previously added callback function from a specific channel.
 * @param channel The channel to unsubscribe from.
 * @param callback The callback function to remove.
 */
export function removeClientCallback(channel: string, callback: NotificationCallback) {
  const subscribers = channelCallbacks.get(channel);
  if (subscribers) {
    subscribers.delete(callback);
    if (subscribers.size === 0) {
      channelCallbacks.delete(channel);
    }
  }
}

/**
 * Initializes the database listener connection.
 * Should be called once during server startup.
 * Safe to call multiple times - will only connect once.
 */
export async function initializeDbListener() {
  // If a connection attempt is already in progress, or a reconnect is scheduled,
  // don't try to connect again. This prevents a tight loop if this function
  // is called repeatedly while the database is down.
  if (!isConnecting && !reconnectTimeout) {
    await connectAndListen();
  }
  
  // Check if the connection is actually working
  let connectionStatus = 'unknown';
  // Use local variable synced with globalThis
  if (pgClient) {
    try {
      // Try a simple query to verify the connection is working
      await pgClient.query('SELECT 1');
      connectionStatus = 'connected';
    } catch (e) {
      connectionStatus = 'error';
      console.error('DB Listener: Connection test failed:', e);
      // Force reconnection
      closeConnectionAndScheduleReconnect();
    }
  } else {
    // Use local variable synced with globalThis
    connectionStatus = isConnecting ? 'connecting' : 'disconnected';
  }

  const activeCallbacks = Array.from(channelCallbacks.values()).reduce((sum, set) => sum + set.size, 0);

  return {
    activeCallbacks: activeCallbacks,
    isConnected: connectionStatus === 'connected',
    status: connectionStatus
  };
}

// --- Initialization ---
// The initializeDbListener() function should be called explicitly
// once during server startup, typically from instrumentation.ts.
