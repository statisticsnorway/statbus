import { NextResponse } from "next/server";
import { Level, LogEvent } from "pino";
import { createClient } from "@/lib/supabase/server";
import { createServerLogger } from "@/lib/logger";

interface ClientLogRequest {
  level: Level;
  event: LogEvent;
  location: Location;
}

export async function POST(request: Request) {
  try {
    const client = createClient();
    const logger = await createServerLogger();
    const {
      data: { session },
    } = await client.auth.getSession();

    const {
      level = "info",
      event,
      location,
    }: ClientLogRequest = await request.json();

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
    console.error(e, "failed to log event");
  }
}
