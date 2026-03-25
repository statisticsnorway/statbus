/**
 * Validates that all required NEXT_PUBLIC_* environment variables are set
 * and don't contain unreplaced __NEXT_PUBLIC_*__ placeholders.
 *
 * Called once at app startup from layout.tsx. Throws immediately if any
 * variable is missing or contains a placeholder — this ensures a clear,
 * early error rather than cryptic failures deep in the component tree.
 *
 * Compatible with local dev (pnpm run dev) where .env provides values,
 * and production Docker where docker-entrypoint.sh injects them at startup.
 */

const REQUIRED_NEXT_PUBLIC_VARS = [
  "NEXT_PUBLIC_BROWSER_REST_URL",
  "NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE",
  "NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME",
] as const;

export function validateEnv() {
  const errors: string[] = [];

  for (const name of REQUIRED_NEXT_PUBLIC_VARS) {
    const value = process.env[name];

    if (!value) {
      errors.push(`${name} is not set`);
      continue;
    }

    if (value.startsWith("__NEXT_PUBLIC_") && value.endsWith("__")) {
      errors.push(
        `${name} contains unreplaced placeholder "${value}" — docker-entrypoint.sh did not run`
      );
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Missing or invalid environment variables:\n${errors.map((e) => `  - ${e}`).join("\n")}\n\n` +
        `If running in Docker: ensure NEXT_PUBLIC_* vars are in docker-compose environment.\n` +
        `If running locally: run ./sb config generate to create .env.`
    );
  }
}
