import { NextResponse } from "next/server";
import { Level, LogEvent } from "pino";

import { createServerLogger } from "@/lib/server-logger";

interface ClientLogRequest {
  level: Level;
  event: LogEvent;
  location: Location;
}

export async function POST(request: Request) {
  try {
    const logger = await createServerLogger();
    const { level = "info", event }: ClientLogRequest = await request.json();
    const payload = event.messages
      ?.filter((message) => typeof message === "object")
      ?.reduce((acc, message) => {
        return { ...acc, ...message };
      }, {});

    logger[level](
      {
        ...payload,
        reporter: "browser",
        useragent: request.headers.get("user-agent"),
      },
      event.messages[event.messages.length - 1]
    );

    return NextResponse.json({ success: true });
  } catch (e) {
    console.error(e, "failed to log event");
  }
}
