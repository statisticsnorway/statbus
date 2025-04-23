/**
 * db-listener.ts - Singleton for managing a persistent PostgreSQL connection
 * to listen for notifications (pg_notify) on the 'check' channel.
 *
 * This module ensures only one listener connection is active per server process
 * and distributes notifications to subscribed SSE clients via callbacks.
 */

import { Client } from 'pg';

// Type for the callback function provided by SSE route handlers
type NotificationCallback = (payload: string) => void;

// Store callbacks in a global registry to persist across module reloads
// @ts-ignore - intentionally using global to persist across hot reloads in development
const activeClientCallbacks = global.__dbListenerCallbacks || new Set<NotificationCallback>();
// @ts-ignore - store in global scope to persist across module reloads
if (typeof global !== 'undefined') {
  global.__dbListenerCallbacks = activeClientCallbacks;
}

// @ts-ignore - store client in global scope to persist across module reloads
const pgClient: Client | null = global.__dbListenerClient || null;
// @ts-ignore - store connection state in global scope
const isConnecting: boolean = global.__dbListenerConnecting || false;
// @ts-ignore - store reconnect timeout in global scope
const reconnectTimeout: NodeJS.Timeout | null = global.__dbListenerReconnectTimeout || null;

// Update global references when these variables change
function updateGlobalClient(client: Client | null) {
  // @ts-ignore
  global.__dbListenerClient = client;
  return client;
}

function updateGlobalConnecting(connecting: boolean) {
  // @ts-ignore
  global.__dbListenerConnecting = connecting;
  return connecting;
}

function updateGlobalReconnectTimeout(timeout: NodeJS.Timeout | null) {
  // @ts-ignore
  global.__dbListenerReconnectTimeout = timeout;
  return timeout;
}

const RECONNECT_DELAY_MS = 5000; // Delay before attempting reconnection


async function connectAndListen() {
  // @ts-ignore - check global client first
  const currentClient = global.__dbListenerClient;
  // @ts-ignore - check global connecting state
  const currentlyConnecting = global.__dbListenerConnecting;
  
  if (currentClient && currentClient.connectionParameters) {
    return;
  }
  
  if (currentlyConnecting) {
    return;
  }

  updateGlobalConnecting(true);

  // Clear any pending reconnect timeout
  // @ts-ignore - check global timeout
  const currentTimeout = global.__dbListenerReconnectTimeout;
  if (currentTimeout) {
    clearTimeout(currentTimeout);
    updateGlobalReconnectTimeout(null);
  }

  try {
    // Construct connection string from individual environment variables
    const dbName = process.env.POSTGRES_APP_DB; // Use the app-specific DB
    const dbUser = process.env.POSTGRES_APP_USER;
    const dbPassword = process.env.POSTGRES_APP_PASSWORD;

    let dbHost: string | undefined;
    let dbPort: string | undefined;

    // Check if DB_PUBLIC_LOCALHOST_PORT is set for local development override
    const localPort = process.env.DB_PUBLIC_LOCALHOST_PORT;
    if (localPort && /^\d+$/.test(localPort)) {
      dbHost = 'localhost';
      dbPort = localPort;
    } else {
      // Default to Docker internal host/port
      dbHost = process.env.POSTGRES_HOST;
      dbPort = process.env.POSTGRES_PORT;
    }

    if (!dbUser || !dbPassword || !dbHost || !dbPort || !dbName) {
      throw new Error('Missing required PostgreSQL connection environment variables (check POSTGRES_APP_*, POSTGRES_HOST, POSTGRES_PORT, DB_PUBLIC_LOCALHOST_PORT)');
    }

    const connectionString = `postgresql://${encodeURIComponent(dbUser)}:${encodeURIComponent(dbPassword)}@${dbHost}:${dbPort}/${encodeURIComponent(dbName)}`;
    // We'll skip this log and only show the connected message

    const newClient = new Client({
      connectionString: connectionString,
      // Add SSL configuration if needed for production
      // ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : undefined,
    });
    
    updateGlobalClient(newClient);

    newClient.on('notification', (msg) => {
      // Handle only the 'check' channel (string payload)
      if (msg.channel === 'check' && msg.payload) {
        // Use a copy of the set to avoid issues if callbacks modify the set during iteration
        const callbacksToNotify = new Set(activeClientCallbacks);
        
        // In development mode, log a single line about the notification
        if (process.env.NODE_ENV === 'development') {
          console.log(`DB Listener: Notification '${msg.payload}' sent to ${callbacksToNotify.size} clients`);
        }
        
        callbacksToNotify.forEach(callback => {
          try {
            callback(msg.payload as string);
          } catch (e) {
            console.error({ error: e }, "DB Listener: Error executing notification callback");
          }
        });
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
    await newClient.query('LISTEN "check";'); // Listen only to the "check" channel (quoted identifier)
    updateGlobalConnecting(false);
    console.log(`DB Listener: Connected to ${dbHost}:${dbPort}/${dbName} as ${dbUser} and listening on "check" channel`);

  } catch (error) {
    updateGlobalConnecting(false);
    console.error({ error }, 'DB Listener: Failed to connect or listen');
    updateGlobalClient(null); // Ensure client is null on failure
    scheduleReconnect(); // Schedule a retry
  }
}

function scheduleReconnect() {
  // @ts-ignore - check global timeout
  const currentTimeout = global.__dbListenerReconnectTimeout;
  
  if (!currentTimeout) {
    const timeout = setTimeout(() => {
      updateGlobalReconnectTimeout(null); // Clear the timeout ID before attempting connection
      connectAndListen();
    }, RECONNECT_DELAY_MS);
    
    updateGlobalReconnectTimeout(timeout);
    console.log(`DB Listener: Reconnection scheduled in ${RECONNECT_DELAY_MS / 1000} seconds`);
  }
}

function closeConnectionAndScheduleReconnect() {
  // @ts-ignore - check global client
  const currentClient = global.__dbListenerClient;
  
  if (currentClient) {
    currentClient.end().catch(err => console.error({ error: err }, 'DB Listener: Error during connection end'));
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
  // @ts-ignore - check global client
  const currentClient = global.__dbListenerClient;
  
  if (currentClient) {
    try {
      // Try a simple query to verify the connection is working
      await currentClient.query('SELECT 1');
      connectionStatus = 'connected';
    } catch (e) {
      connectionStatus = 'error';
      console.error('DB Listener: Connection test failed:', e);
      // Force reconnection
      closeConnectionAndScheduleReconnect();
    }
  } else {
    // @ts-ignore - check global connecting state
    connectionStatus = global.__dbListenerConnecting ? 'connecting' : 'disconnected';
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
