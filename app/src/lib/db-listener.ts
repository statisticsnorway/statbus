/**
 * db-listener.ts - Singleton for managing a persistent PostgreSQL connection
 * to listen for notifications (pg_notify) on the 'check' channel.
 *
 * This module ensures only one listener connection is active per server process
 * and distributes notifications to subscribed SSE clients via callbacks.
 */

import { Client } from 'pg';

// Extend the global NodeJS namespace to declare our custom properties
// This helps persist state across hot module reloads in development
declare global {
  // eslint-disable-next-line no-var
  var __dbListenerCallbacks: Set<NotificationCallback> | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerClient: Client | null | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerConnecting: boolean | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerReconnectTimeout: NodeJS.Timeout | null | undefined;
  // eslint-disable-next-line no-var
  var __dbListenerDebounceTimers: { [key: string]: NodeJS.Timeout } | undefined;
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
  const dbUser = getRequiredEnvVar('POSTGRES_APP_USER');
  // Password might be optional in some environments (e.g., local dev with trust auth)
  const dbPassword = process.env.POSTGRES_APP_PASSWORD || ''; // Default to empty string if not set

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

  // Check if DB_PUBLIC_LOCALHOST_PORT is set for local development override
  const localPortStr = process.env.DB_PUBLIC_LOCALHOST_PORT;
  if (localPortStr) {
    // Validate localPortStr format before parsing
    if (!/^\d+$/.test(localPortStr)) {
       throw new Error(`Invalid format for environment variable DB_PUBLIC_LOCALHOST_PORT: ${localPortStr}. Must be a number.`);
    }
    dbHost = 'localhost';
    dbPort = parsePort(localPortStr, 'DB_PUBLIC_LOCALHOST_PORT');
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
export type WorkerStatusPayload = { type: string; status: boolean };

export type ImportJobNotificationPayload = {
  verb: string;
  id: number;
};

// Create a discriminated union based on the channel
export type NotificationData =
  | { channel: 'worker_status'; payload: WorkerStatusPayload }
  | { channel: 'import_job'; payload: ImportJobNotificationPayload };

// Type for the callback function provided by SSE route handlers
export type NotificationCallback = (data: NotificationData) => void;

// Use globalThis for broader compatibility and type safety with declared globals
const activeClientCallbacks = globalThis.__dbListenerCallbacks || new Set<NotificationCallback>();
if (typeof globalThis !== 'undefined') {
  globalThis.__dbListenerCallbacks = activeClientCallbacks;
}

let pgClient: Client | null = globalThis.__dbListenerClient || null;
let isConnecting: boolean = globalThis.__dbListenerConnecting || false;
let reconnectTimeout: NodeJS.Timeout | null = globalThis.__dbListenerReconnectTimeout || null;

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
    // Send the latest status to all connected clients
    activeClientCallbacks.forEach(callback => callback({
      channel: 'worker_status',
      payload: payload,
    }));
    delete debounceTimers[payload.type]; // Clean up timer
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

const RECONNECT_DELAY_MS = 5000; // Delay before attempting reconnection


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

  try {
    // Get database connection details
    const { dbName, dbUser, dbPassword, dbHost, dbPort } = getDbHostPort();

    const connectionString = `postgresql://${encodeURIComponent(dbUser)}:${encodeURIComponent(dbPassword)}@${dbHost}:${dbPort}/${encodeURIComponent(dbName)}`;
    // We'll skip this log and only show the connected message

    const newClient = new Client({
      connectionString: connectionString,
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
      } else if (msg.channel === 'import_job') {
        // Handle 'import_job' channel (JSON payload with verb and id)
        // The outer check `if (!msg.payload) return;` ensures payload is defined here.
        try {
          const data = JSON.parse(msg.payload) as ImportJobNotificationPayload;
          // Use a copy of the set to avoid issues if callbacks modify the set during iteration
          const callbacksToNotify = new Set(activeClientCallbacks);
          callbacksToNotify.forEach(callback => {
            callback({
              channel: 'import_job',
              payload: data
            });
          });

          if (process.env.NODE_ENV === 'development') {
            console.log(`DB Listener: Import job notification - ${data.verb} for job ${data.id}`);
          }
        } catch (e) {
          console.error({ error: e, payload: msg.payload }, "DB Listener: Error parsing import_job notification");
          throw e;
        }
      }
    });

    newClient.on('error', (err) => {
      console.error({ error: err }, 'DB Listener: Connection error');
      // Connection might be lost, attempt reconnection
      closeConnectionAndScheduleReconnect();
    });

    newClient.on('end', () => {
      console.warn('DB Listener: Connection ended.');
      // Connection ended unexpectedly, attempt reconnection
      closeConnectionAndScheduleReconnect();
    });

    await newClient.connect();
    await newClient.query('LISTEN "worker_status";'); // Listen to the new "worker_status" channel
    await newClient.query('LISTEN "import_job";'); // Listen to the "import_job" channel
    updateGlobalConnecting(false);
    console.log(`DB Listener: Connected to ${dbHost}:${dbPort}/${dbName} as ${dbUser} and listening on "worker_status" and "import_job" channels`);

  } catch (error) {
    updateGlobalConnecting(false);
    console.error({ error }, 'DB Listener: Failed to connect or listen');
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
    }, RECONNECT_DELAY_MS);
    
    updateGlobalReconnectTimeout(timeout);
    console.log(`DB Listener: Reconnection scheduled in ${RECONNECT_DELAY_MS / 1000} seconds`);
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
 * Adds a callback function to be invoked when a 'check' notification is received.
 * @param callback Function to call with the notification payload (string).
 */
export function addClientCallback(callback: NotificationCallback) {
  activeClientCallbacks.add(callback);
}

/**
 * Removes a previously added callback function.
 * @param callback The callback function to remove.
 */
export function removeClientCallback(callback: NotificationCallback) {
  activeClientCallbacks.delete(callback);
}

/**
 * Initializes the database listener connection.
 * Should be called once during server startup.
 * Safe to call multiple times - will only connect once.
 */
export async function initializeDbListener() {
  await connectAndListen();
  
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

  return {
    activeCallbacks: activeClientCallbacks.size,
    isConnected: connectionStatus === 'connected',
    status: connectionStatus
  };
}

// --- Initialization ---
// The initializeDbListener() function should be called explicitly
// once during server startup, typically from instrumentation.ts.
