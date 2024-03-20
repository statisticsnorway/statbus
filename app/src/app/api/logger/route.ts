import { NextResponse } from "next/server";
import logger from "@/lib/logger";
import type { Level } from "pino";

interface LogRequest {
  level: Level;
  event: any;
}

export async function POST(request: Request) {
  try {
    const { level = "error", event }: LogRequest = await request.json();
    logger[level](event, "client log event");
    return NextResponse.json({ success: true });
  } catch (e) {
    logger.error({ error: e }, "failed to log event");
  }
}
