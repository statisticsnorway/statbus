import { NextResponse } from "next/server";
import logger from "@/lib/logger";
import { Level, LogEvent } from "pino";
import { createClient } from "@/lib/supabase/server";

interface ClientLogRequest {
  level: Level;
  event: LogEvent;
  location: Location;
}

export async function POST(request: Request) {
  try {
    const client = createClient();
    const {
      data: { session },
    } = await client.auth.getSession();

    const {
      level = "info",
      event,
      location,
    }: ClientLogRequest = await request.json();

    /**
     * The logger may have been called with
     */
    const payload = event.messages
      ?.filter((message) => typeof message === "object")
      ?.reduce((acc, message) => {
        return { ...acc, ...message };
      }, {});

    logger[level](
      {
        ...payload,
        location,
        reporter: "browser",
        useragent: request.headers.get("user-agent"),
        user: session?.user.email,
      },
      event.messages[event.messages.length - 1]
    );

    return NextResponse.json({ success: true });
  } catch (e) {
    logger.error(e, "failed to log event");
  }
}
