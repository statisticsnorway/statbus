"use client";

/**
 * Login Page UI State Machine (loginUiMachine)
 *
 * This file defines a state machine that controls the UI of the /login page.
 * It is a "presentation" machine, meaning its sole responsibility is to decide
 * what should be rendered on the login page based on the current context.
 *
 * Responsibilities:
 * - Deciding whether to show the login form, a loading/finalizing message, or nothing.
 *
 * Interactions:
 * - It receives context (isAuthenticated, isLoggingIn, isOnLoginPage) from the
 *   `LoginClientBoundary` component.
 * - It does NOT perform the login API call; that is handled by `authMachine`.
 * - It does NOT handle redirecting the user away from the login page; that is
 *   handled by `navigationMachine`.
 */

import { atom } from 'jotai'
import { atomEffect } from 'jotai-effect'
import { createMachine, assign, setup, type SnapshotFrom } from 'xstate'
import { atomWithMachine } from 'jotai-xstate'

import { inspector } from './inspector';

export const loginUiMachine = setup({
  types: {
    context: {} as {
      isAuthenticated: boolean;
      isLoggingIn: boolean;
      isOnLoginPage: boolean;
    },
    events: {} as
      | { type: 'EVALUATE'; context: { isAuthenticated: boolean; isLoggingIn: boolean; isOnLoginPage: boolean; } },
  },
}).createMachine({
  id: 'loginUi',
  initial: 'idle',
  context: {
    isAuthenticated: false,
    isLoggingIn: false,
    isOnLoginPage: false,
  },
  states: {
    idle: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign(({ event }) => event.context)
        }
      }
    },
    evaluating: {
      always: [
        { target: 'finalizing', guard: ({ context }) => context.isOnLoginPage && (context.isAuthenticated || context.isLoggingIn) },
        { target: 'showingForm', guard: ({ context }) => context.isOnLoginPage && !context.isAuthenticated },
        { target: 'idle' } // If not on login page, do nothing.
      ]
    },
    showingForm: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign(({ event }) => event.context)
        }
      }
    },
    finalizing: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign(({ event }) => event.context)
        }
      }
    }
  }
});

export const loginUiMachineAtom = atomWithMachine(loginUiMachine, {
  inspect: inspector,
});
