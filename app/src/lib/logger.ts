import pino from "pino";
import { createStream } from "pino-seq";

const logServerUrl = process.env.LOG_SERVER || "http://localhost:5341";

const logger = pino(
  {
    level: "info",
    name: "statbus app",
    browser: {
      disabled: true,
      transmit: {
        level: "error",
        send: async function (level, event) {
          try {
            await fetch("/api/logger", {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
              },
              body: JSON.stringify({ level, event, location }),
            });
          } catch (e) {
            console.error("failed to send log to server", e);
          }
        },
      },
    },
  },
  typeof window === "undefined"
    ? createStream({ serverUrl: logServerUrl })
    : undefined
);

const child = logger.child({
  version: process.env.VERSION,
  reporter: "server",
});

export default child;
