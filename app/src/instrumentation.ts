/**
 * instrumentation.ts
 *
 * This file allows hooking into the Next.js server lifecycle.
 * Next.js automatically detects this file and runs the exported `register`
 * function once when the server process starts.
 * We use it here to initialize server-side singletons like the DB listener.
 * See: https://nextjs.org/docs/app/building-your-application/optimizing/instrumentation
 */

// Ensure this function is exported from the file
export async function register() {
  // Check if we're running in the server environment before initializing
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    // Dynamically import the listener to avoid issues in edge runtimes
    const { initializeDbListener } = await import('@/lib/db-listener');
    try {
      await initializeDbListener();
    } catch (error) {
      console.error("Instrumentation: DB Listener initialization failed:", error);
    }
  }
}
