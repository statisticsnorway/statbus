"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import pino from "pino";
import { headers } from "next/headers";

const seqServerUrl = process.env.SEQ_SERVER_URL || "http://localhost:5341";
const seqApiKey = process.env.SEQ_API_KEY;

/**
 * Create a pino logger for the server that includes the user's email and the app version
 * @param user Optional user object with email property
 */
export async function createServerLogger(user?: { email: string } | null) {
  const client = await getServerRestClient();
  
  // Dynamic import to handle ESM module
  // Note: pino-seq exports as default in index.js (ES module) but uses export = in index.d.ts (CommonJS types)
  // Runtime: export default { createStream: ... }
  // Types: export = PinoSeq (namespace with createStream function)
  const pinoSeqModule = await import("pino-seq");
  const pinoToSeq = (pinoSeqModule as any).default || pinoSeqModule;
  const stream = pinoToSeq.createStream({ serverUrl: seqServerUrl, apiKey: seqApiKey });

  return pino(
    {
      level: process.env.LOG_LEVEL || "info",
      base: {
        version: process.env.VERSION,
        user: user?.email,
        reporter: "server",
        referer: (await headers()).get("referer"),
      },
    },
    stream
  );
}
