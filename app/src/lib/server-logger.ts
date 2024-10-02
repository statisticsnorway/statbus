"use server";
import { createClient } from "@/utils/supabase/server";
import pino from "pino";
import { createStream } from "pino-seq";
import { headers } from "next/headers";

const seqServerUrl = process.env.SEQ_SERVER_URL || "http://localhost:5341";
const seqApiKey = process.env.SEQ_API_KEY;

/**
 * Create a pino logger for the server that includes the user's email and the app version
 */
export async function createServerLogger() {
  const { client } = createClient();

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
        referer: headers().get("referer"),
      },
    },
    createStream({ serverUrl: seqServerUrl, apiKey: seqApiKey })
  );
}
