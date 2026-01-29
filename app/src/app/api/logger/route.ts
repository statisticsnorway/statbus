import { NextResponse, NextRequest } from "next/server";
import { LogEvent, Logger } from "pino";

import { createServerLogger } from "@/lib/server-logger";
import { getServerRestClient } from "@/context/RestClientStore";

// Valid Pino log levels - used to validate user input before dynamic method call
const VALID_LOG_LEVELS = ['trace', 'debug', 'info', 'warn', 'error', 'fatal'] as const;
type ValidLogLevel = (typeof VALID_LOG_LEVELS)[number];

const isValidLogLevel = (level: unknown): level is ValidLogLevel =>
  typeof level === 'string' && VALID_LOG_LEVELS.includes(level as ValidLogLevel);

// Interface for log requests
interface ClientLogRequest {
  level: string;
  event: LogEvent;
  location: Location;
}

// Maximum allowed size for non-authenticated logs
const MAX_LOG_SIZE = 256; // Set your size limit here, e.g., 100 characters

// Function to parse log request payload
const parseLogPayload = (event: LogEvent) => {
  return event.messages
    ?.filter((message) => typeof message === "object")
    ?.reduce((acc, message) => {
      return { ...acc, ...message };
    }, {});
};

// Function to limit data size
const limitDataSize = (payload: any, maxSize: number) => {
  const limitedPayload: any = {};
  for (const key in payload) {
    if (typeof payload[key] === "string" && payload[key].length > maxSize) {
      limitedPayload[key] = payload[key].substring(0, maxSize) + '...';
    } else {
      limitedPayload[key] = payload[key];
    }
  }
  return limitedPayload;
};

// Function to log events - level is validated before this function is called
const logEvent = async (logger: Logger<never>, level: ValidLogLevel, payload: any, event: LogEvent, useragent: string) => {
  logger[level](
    {
      ...payload,
      reporter: "browser",
      useragent: useragent,
    },
    event.messages[event.messages.length - 1]
  );
};

export async function POST(request: NextRequest) {
  try {
    const logger = await createServerLogger();
    const { level = "info", event }: ClientLogRequest = await request.json();

    // Validate log level to prevent unvalidated dynamic method call (CodeQL js/unvalidated-dynamic-method-call)
    if (!isValidLogLevel(level)) {
      return NextResponse.json(
        { success: false, error: "Invalid log level" },
        { status: 400 }
      );
    }

    const client = await getServerRestClient();
    // Check for authentication using cookies instead of client.auth
    const isLoggedIn = request.cookies.has('statbus');


    // Parse the payload
    const payload = parseLogPayload(event);

    const userAgent = request.headers.get("user-agent") ?? "unknown";

    // If session exists, log normally; otherwise, limit data
    if (isLoggedIn) {
      await logEvent(logger, level, payload, event, userAgent);
    } else {
      // Limit log data for non-authenticated users
      const limitedPayload = limitDataSize(payload, MAX_LOG_SIZE);
      await logEvent(logger, level, limitedPayload, event, userAgent);
    }

    return NextResponse.json({ success: true });

  } catch (e) {
    console.error(e, "failed to log event");
    return NextResponse.json({ success: false, error: "Failed to log event" }, { status: 500 });
  }
}
