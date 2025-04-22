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
  // The register function can run in edge environments too in some configurations.
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    console.log("Instrumentation: Registering server-side components...");
    // Dynamically import the listener to avoid issues if it's not needed
    // in edge runtimes or during build steps where the DB might not be available.
    const { initializeDbListener } = await import('@/lib/db-listener');
    await initializeDbListener();
    console.log("Instrumentation: DB Listener initialization initiated.");
  } else {
    console.log("Instrumentation: Skipping server-side initialization (runtime:", process.env.NEXT_RUNTIME, ")");
  }
}
