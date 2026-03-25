/**
 * Validates that no NEXT_PUBLIC_* environment variable contains an
 * unreplaced __NEXT_PUBLIC_*__ placeholder from the Docker build.
 *
 * Called once at app startup from layout.tsx. Throws immediately if any
 * placeholder leaked through — this ensures a clear, early error rather
 * than cryptic failures deep in the component tree.
 *
 * No hardcoded list — scans every NEXT_PUBLIC_* key in process.env.
 *
 * Compatible with local dev (pnpm run dev) where .env provides values,
 * and production Docker where docker-entrypoint.sh injects them at startup.
 */

export function validateEnv() {
  const errors: string[] = [];

  for (const [name, value] of Object.entries(process.env)) {
    if (!name.startsWith("NEXT_PUBLIC_")) continue;
    if (!value) continue;

    if (value.startsWith("__NEXT_PUBLIC_") && value.endsWith("__")) {
      errors.push(
        `${name} contains unreplaced placeholder "${value}"`
      );
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Unreplaced NEXT_PUBLIC_* placeholders detected:\n${errors.map((e) => `  - ${e}`).join("\n")}\n\n` +
        `The docker-entrypoint.sh did not inject runtime values.\n` +
        `Ensure NEXT_PUBLIC_* vars are set in docker-compose environment block.\n` +
        `If running locally: run ./sb config generate to create .env.`
    );
  }
}
