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

// Store callbacks for active SSE connections
const activeClientCallbacks = new Set<NotificationCallback>();
let pgClient: Client | null = null;
let isConnecting = false;
let reconnectTimeout: NodeJS.Timeout | null = null;

const RECONNECT_DELAY_MS = 5000; // Delay before attempting reconnection


async function connectAndListen() {
  if (pgClient || isConnecting) {
    console.debug('DB Listener: Connection attempt skipped (already connected or connecting).');
    return;
  }

  isConnecting = true;
  console.info('DB Listener: Attempting to connect...');

  // Clear any pending reconnect timeout
  if (reconnectTimeout) {
    clearTimeout(reconnectTimeout);
    reconnectTimeout = null;
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
      console.info(`DB Listener: Using localhost override port ${localPort}`);
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
    console.info(`DB Listener: Connecting with user ${dbUser} to ${dbHost}:${dbPort}/${dbName}`);

    pgClient = new Client({
      connectionString: connectionString,
      // Add SSL configuration if needed for production
      // ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : undefined,
    });

    pgClient.on('notification', (msg) => {
      console.debug({ channel: msg.channel, payload: msg.payload }, 'DB Listener: Received notification');
      // Handle only the 'check' channel (string payload)
      if (msg.channel === 'check' && msg.payload) {
        // Payload for 'check' is just the function name string
        // Use a copy of the set to avoid issues if callbacks modify the set during iteration
        const callbacksToNotify = new Set(activeClientCallbacks);
        callbacksToNotify.forEach(callback => {
          try {
            callback(msg.payload as string);
          } catch (e) {
            console.error({ error: e, callback: callback.name }, "DB Listener: Error executing notification callback");
            // Optionally remove problematic callbacks? For now, just log.
          }
        });
      }
    });

    pgClient.on('error', (err) => {
      console.error({ error: err }, 'DB Listener: Connection error');
      // Connection might be lost, attempt reconnection
      closeConnectionAndScheduleReconnect();
    });

    pgClient.on('end', () => {
      console.warn('DB Listener: Connection ended.');
      // Connection ended unexpectedly, attempt reconnection
      closeConnectionAndScheduleReconnect();
    });

    await pgClient.connect();
    await pgClient.query('LISTEN "check";'); // Listen only to the "check" channel (quoted identifier)
    isConnecting = false;
    console.info('DB Listener: Successfully connected and listening on "check" channel.');

  } catch (error) {
    isConnecting = false;
    console.error({ error }, 'DB Listener: Failed to connect or listen');
    pgClient = null; // Ensure client is null on failure
    scheduleReconnect(); // Schedule a retry
  }
}

function scheduleReconnect() {
  if (!reconnectTimeout) {
    console.warn(`DB Listener: Scheduling reconnection attempt in ${RECONNECT_DELAY_MS / 1000} seconds.`);
    reconnectTimeout = setTimeout(() => {
      reconnectTimeout = null; // Clear the timeout ID before attempting connection
      connectAndListen();
    }, RECONNECT_DELAY_MS);
  } else {
    console.debug('DB Listener: Reconnection already scheduled.');
  }
}

function closeConnectionAndScheduleReconnect() {
  if (pgClient) {
    console.warn('DB Listener: Closing existing connection due to error or end event.');
    pgClient.end().catch(err => console.error({ error: err }, 'DB Listener: Error during connection end'));
    pgClient = null;
  }
  isConnecting = false; // Ensure we allow a new connection attempt
  scheduleReconnect();
}

// --- Public API ---

/**
 * Adds a callback function to be invoked when a 'check' notification is received.
 * @param callback Function to call with the notification payload (string).
 */
export function addClientCallback(callback: NotificationCallback) {
  activeClientCallbacks.add(callback);
  console.debug(`DB Listener: Added client callback. Total callbacks: ${activeClientCallbacks.size}`);
}

/**
 * Removes a previously added callback function.
 * @param callback The callback function to remove.
 */
export function removeClientCallback(callback: NotificationCallback) {
  activeClientCallbacks.delete(callback);
  console.debug(`DB Listener: Removed client callback. Total callbacks: ${activeClientCallbacks.size}`);
}

/**
 * Initializes the database listener connection.
 * Should be called once during server startup.
 */
export async function initializeDbListener() {
  // No logger setup needed anymore
  await connectAndListen();
}

// --- Initialization ---
// The initializeDbListener() function should be called explicitly
// once during server startup, typically from instrumentation.ts.
