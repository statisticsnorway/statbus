// src/stores.ts
import { writable } from 'svelte/store';

// Possible options: "white" | "g10" | "g80" | "g90" | "g100"
export const themeStore = writable("g100"); // default theme
