import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDate(date: Date): string {
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric'
  });
}

export function formatDuration(seconds: number): string {
  if (seconds < 0 || !isFinite(seconds)) {
    return "";
  }
  if (seconds < 1) {
    return "< 1s";
  }

  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);

  const parts = [];
  if (h > 0) {
    parts.push(`${h}h`);
  }
  if (m > 0) {
    parts.push(`${m}m`);
  }
  // Only show seconds if total time is less than an hour for brevity
  if (s > 0 && h === 0) {
    parts.push(`${s}s`);
  }

  return parts.join(' ');
}
