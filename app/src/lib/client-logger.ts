import pino from "pino";

const logger = pino({
  level: "info",
  browser: {
    transmit: {
      level: "error",
      send: async function (level, event) {
        try {
          await fetch("/api/logger", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ level, event }),
          });
        } catch (e) {
          console.error("failed to send log to server", e);
        }
      },
    },
  },
});

export default logger;
