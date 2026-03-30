/**
 * Validates that required server-side environment variables are set.
 *
 * Called once at app startup from layout.tsx. These env vars are read
 * server-side by layout.tsx and injected into the HTML as
 * window.__STATBUS_CONFIG__. Client code reads from there, not process.env.
 */

export function validateEnv() {
  // Skip during next build — env vars may not be set yet.
  if (process.env.NEXT_PHASE === "phase-production-build") return;

  const required = [
    "NEXT_PUBLIC_BROWSER_REST_URL",
    "NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME",
    "NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE",
  ];

  const missing = required.filter((name) => !process.env[name]);

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables:\n${missing.map((e) => `  - ${e}`).join("\n")}\n\n` +
        `Run ./sb config generate to create .env, or set them in docker-compose.`
    );
  }
}
