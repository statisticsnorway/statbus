import pino, { Level, LogEvent } from "pino";

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
    ? pino.destination("statbus-server.log")
    : undefined
);

export default logger;
