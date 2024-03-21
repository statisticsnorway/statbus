import { createClient } from "@/lib/supabase/server";
import pino from "pino";
import { createStream } from "pino-seq";

const logServerUrl = process.env.LOG_SERVER || "http://localhost:5341";

/**
 * Create a pino logger for the server that includes the user's email and the app version
 */
export async function createServerLogger() {
  const client = createClient();

  const {
    data: { session },
  } = await client.auth.getSession();

  return pino(
    {
      level: process.env.LOG_LEVEL || "info",
      base: {
        version: process.env.VERSION,
        user: session?.user.email,
        reporter: "server",
      },
    },
    createStream({ serverUrl: logServerUrl })
  );
}
