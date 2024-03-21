import { NextResponse } from "next/server";
import logger from "@/lib/logger";
import { Level, LogEvent } from "pino";

interface ClientLogRequest {
  level: Level;
  event: LogEvent;
  location: Location;
}

export async function POST(request: Request) {
  try {
    const {
      level = "info",
      event,
      location,
    }: ClientLogRequest = await request.json();
    const messages = event.messages;
    const data = messages.slice(0, -1)?.reduce((acc, curr) => {
      return { ...acc, ...curr };
    }, {});
    logger[level]({ ...data, location }, messages[messages.length - 1]);
    return NextResponse.json({ success: true });
  } catch (e) {
    logger.error({ error: e }, "failed to log event");
  }
}
