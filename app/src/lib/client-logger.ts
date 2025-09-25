"use client";

import { isDebugInspectorUIVisible } from '@/atoms/inspector';

type LogLevel = 'debug' | 'info' | 'warn' | 'error';
type LogCall = { level: LogLevel; context: string; message: string; args: any[] };

class ClientLogger {
  private buffer: LogCall[] = [];
  private isInitialized = false;

  /**
   * Called once the application has mounted and the inspector's visibility
   * state is known. Flushes any buffered debug messages if the inspector is visible.
   */
  public initialize() {
    this.isInitialized = true;
    if (isDebugInspectorUIVisible) {
      this.buffer.forEach(({ level, context, message, args }) => {
        // We use this.log directly to bypass buffering and print the message.
        this.log(level, context, message, ...args);
      });
    }
    // Clear the buffer regardless, as it's no longer needed.
    this.buffer = [];
  }

  private log(level: LogLevel, context: string, message: string, ...args: any[]) {
    // During the brief period before initialization, buffer debug messages.
    // Other levels are logged immediately.
    if (!this.isInitialized && level === 'debug') {
      this.buffer.push({ level, context, message, args });
      return;
    }

    // After initialization, debug messages are only shown if the inspector is visible.
    // This keeps the console clean during normal development.
    if (level === 'debug' && !isDebugInspectorUIVisible) {
      return;
    }

    const timestamp = new Date().toLocaleTimeString();
    const formattedMessage = `${timestamp} [${level.toUpperCase()}] [${context}] ${message}`;

    switch (level) {
      case 'debug':
        // eslint-disable-next-line no-console
        console.log(formattedMessage, ...args);
        break;
      case 'info':
        // eslint-disable-next-line no-console
        console.info(formattedMessage, ...args);
        break;
      case 'warn':
        // eslint-disable-next-line no-console
        console.warn(formattedMessage, ...args);
        break;
      case 'error':
        // eslint-disable-next-line no-console
        console.error(formattedMessage, ...args);
        break;
    }
  }

  public debug(context: string, message: string, ...args: any[]) {
    this.log('debug', context, message, ...args);
  }

  public info(context: string, message: string, ...args: any[]) {
    this.log('info', context, message, ...args);
  }

  public warn(context: string, message: string, ...args: any[]) {
    this.log('warn', context, message, ...args);
  }

  public error(context: string, message: string, ...args: any[]) {
    this.log('error', context, message, ...args);
  }
}

export const logger = new ClientLogger();
