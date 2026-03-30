/**
 * Runtime configuration injected by the server via <script> in layout.tsx.
 *
 * This replaces the NEXT_PUBLIC_* build-time inlining pattern. Values are
 * read from process.env on the server at request time and injected into the
 * HTML as window.__STATBUS_CONFIG__. Client code reads from here instead of
 * process.env, avoiding browser cache staleness when config changes.
 */

export interface StatbusConfig {
  browserRestUrl: string;
  deploymentSlotName: string;
  deploymentSlotCode: string;
  debug: boolean;
  version: string;
  commit: string;
}

const SSR_DEFAULTS: StatbusConfig = {
  browserRestUrl: "",
  deploymentSlotName: "",
  deploymentSlotCode: "",
  debug: false,
  version: "",
  commit: "",
};

/**
 * Client-side runtime config. Reads from window.__STATBUS_CONFIG__ which is
 * injected by layout.tsx at request time. Returns defaults during SSR.
 */
export const statbusConfig: StatbusConfig =
  typeof window !== "undefined" && (window as any).__STATBUS_CONFIG__
    ? ((window as any).__STATBUS_CONFIG__ as StatbusConfig)
    : SSR_DEFAULTS;
