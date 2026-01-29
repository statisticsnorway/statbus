"use client";

import React, { useState } from "react";
import { cn } from "@/lib/utils";
import { ChevronDown, ChevronRight, Copy, Check } from "lucide-react";

interface ErrorDisplayProps {
  errors: Record<string, string> | null | undefined;
  variant?: "errors" | "invalid_codes";
  className?: string;
}

/**
 * Extracts the main error message from an error object.
 * Handles cases where errors have nested context/stack traces.
 */
function extractMainError(value: string): string {
  // If it contains "process_batch_error" or similar, extract just that part
  if (value.includes("process_batch_error")) {
    const match = value.match(/"process_batch_error"\s*:\s*"([^"]+)"/);
    if (match) return match[1];
  }
  if (value.includes("error_in_processing_batch")) {
    const match = value.match(/"error_in_processing_batch"\s*:\s*"([^"]+)"/);
    if (match) return match[1];
  }
  // Truncate very long messages (e.g., SQL context)
  if (value.length > 100) {
    // Try to find a meaningful part before SQL context
    const contextIndex = value.indexOf("SQL statement");
    if (contextIndex > 0) {
      return value.substring(0, contextIndex).trim();
    }
    return value.substring(0, 100) + "...";
  }
  return value;
}

/**
 * Formats a field name from snake_case to Title Case.
 */
function formatFieldName(field: string): string {
  return field
    .replace(/_raw$/, "") // Remove _raw suffix
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/**
 * Displays import errors or invalid_codes in a readable format.
 * 
 * - Compact by default, showing truncated error message
 * - Expandable on click to show full details
 * - Copy button to copy full error text
 */
export function ErrorDisplay({ errors, variant = "errors", className }: ErrorDisplayProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [copied, setCopied] = useState(false);

  if (!errors || (typeof errors === "object" && Object.keys(errors).length === 0)) {
    return null;
  }

  // Handle case where errors is a string (shouldn't happen, but be safe)
  let parsedErrors = errors;
  if (typeof errors === "string") {
    try {
      parsedErrors = JSON.parse(errors);
    } catch {
      return (
        <div className={cn("text-xs", className)}>
          <span className="text-red-600">{errors}</span>
        </div>
      );
    }
  }

  const entries = Object.entries(parsedErrors).filter(([key, value]) => {
    // Skip the "context" key which contains SQL stack traces
    if (key === "context") return false;
    // Skip empty values
    if (value === null || value === undefined || value === "") return false;
    return true;
  });

  if (entries.length === 0) {
    return null;
  }

  const isError = variant === "errors";
  const bgColor = isError ? "bg-red-50" : "bg-amber-50";
  const borderColor = isError ? "border-red-200" : "border-amber-200";
  const textColor = isError ? "text-red-700" : "text-amber-700";
  const labelColor = isError ? "text-red-600" : "text-amber-600";
  const hoverBg = isError ? "hover:bg-red-100" : "hover:bg-amber-100";

  // Build copyable text
  const copyText = entries
    .map(([field, value]) => `${formatFieldName(field)}: ${String(value)}`)
    .join("\n");

  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation();
    await navigator.clipboard.writeText(copyText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // Get first error for compact view
  const firstEntry = entries[0];
  const firstError = extractMainError(String(firstEntry[1]));
  const hasMore = entries.length > 1;

  return (
    <div
      className={cn(
        "text-xs rounded border cursor-pointer transition-colors",
        bgColor,
        borderColor,
        hoverBg,
        className
      )}
      onClick={() => setIsExpanded(!isExpanded)}
    >
      {/* Compact view */}
      {!isExpanded && (
        <div className="px-2 py-1 flex items-center gap-1">
          <ChevronRight className={cn("h-3 w-3 flex-shrink-0", labelColor)} />
          <span className={cn("font-medium truncate", textColor)} title={firstError}>
            {firstError}
          </span>
          {hasMore && (
            <span className={cn("text-[10px] flex-shrink-0", labelColor)}>
              +{entries.length - 1}
            </span>
          )}
        </div>
      )}

      {/* Expanded view */}
      {isExpanded && (
        <div className="px-2 py-1.5">
          <div className="flex items-center justify-between mb-1">
            <div className="flex items-center gap-1">
              <ChevronDown className={cn("h-3 w-3", labelColor)} />
              <span className={cn("text-[10px] font-medium", labelColor)}>
                {entries.length} {entries.length === 1 ? "issue" : "issues"}
              </span>
            </div>
            <button
              onClick={handleCopy}
              className={cn(
                "p-0.5 rounded transition-colors",
                isError ? "hover:bg-red-200" : "hover:bg-amber-200"
              )}
              title="Copy to clipboard"
            >
              {copied ? (
                <Check className={cn("h-3 w-3", labelColor)} />
              ) : (
                <Copy className={cn("h-3 w-3", labelColor)} />
              )}
            </button>
          </div>
          <div className="space-y-1.5">
            {entries.map(([field, value]) => (
              <div key={field} className="border-t border-current/10 pt-1">
                <div className={cn("text-[10px] mb-0.5", labelColor)}>
                  {formatFieldName(field)}
                </div>
                <div className={cn("font-medium break-words", textColor)}>
                  {String(value)}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * A compact version that shows just field names as badges.
 * Hovering reveals the full error details.
 */
interface JobErrorDisplayProps {
  error: string | null | undefined;
  className?: string;
}

/**
 * Parses a job-level error string (JSON) and extracts meaningful parts.
 */
function parseJobError(errorString: string): {
  mainError: string;
  context: string | null;
  additionalFields: Record<string, string>;
} {
  try {
    const parsed = JSON.parse(errorString);
    let mainError = "";
    let context = null;
    const additionalFields: Record<string, string> = {};

    for (const [key, value] of Object.entries(parsed)) {
      if (key === "context" && typeof value === "string") {
        context = value;
      } else if (
        key === "error_in_processing_batch" ||
        key === "process_batch_error" ||
        key === "error"
      ) {
        mainError = String(value);
      } else if (value !== null && value !== undefined && value !== "") {
        additionalFields[key] = String(value);
      }
    }

    // If no main error found, use the first non-context field
    if (!mainError && Object.keys(additionalFields).length > 0) {
      const firstKey = Object.keys(additionalFields)[0];
      mainError = additionalFields[firstKey];
      delete additionalFields[firstKey];
    }

    return { mainError, context, additionalFields };
  } catch {
    // Not valid JSON, return as-is
    return { mainError: errorString, context: null, additionalFields: {} };
  }
}

/**
 * Formats the SQL context/stack trace for readability.
 * Extracts function names and shows them as a call stack.
 */
function formatContextAsCallStack(context: string): string[] {
  const lines = context.split("\n");
  const callStack: string[] = [];

  for (const line of lines) {
    // Match patterns like "PL/pgSQL function admin.import_job_process(integer) line 158 at assignment"
    const funcMatch = line.match(/PL\/pgSQL function ([\w.]+\([^)]*\))/);
    if (funcMatch) {
      callStack.push(funcMatch[1]);
    }
  }

  return callStack;
}

/**
 * Displays a job-level error in a readable format.
 * Used in the job error dialog.
 */
export function JobErrorDisplay({ error, className }: JobErrorDisplayProps) {
  const [showContext, setShowContext] = useState(false);
  const [copied, setCopied] = useState(false);

  if (!error) {
    return null;
  }

  const { mainError, context, additionalFields } = parseJobError(error);
  const callStack = context ? formatContextAsCallStack(context) : [];

  const handleCopy = async () => {
    await navigator.clipboard.writeText(error);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className={cn("space-y-4", className)}>
      {/* Main error message */}
      <div className="p-4 bg-red-50 border border-red-200 rounded-md">
        <div className="flex items-start justify-between gap-2">
          <div className="font-medium text-red-800">{mainError}</div>
          <button
            onClick={handleCopy}
            className="p-1.5 rounded hover:bg-red-100 transition-colors flex-shrink-0"
            title="Copy full error to clipboard"
          >
            {copied ? (
              <Check className="h-4 w-4 text-green-600" />
            ) : (
              <Copy className="h-4 w-4 text-red-600" />
            )}
          </button>
        </div>
      </div>

      {/* Additional fields */}
      {Object.keys(additionalFields).length > 0 && (
        <div className="space-y-2">
          <div className="text-sm font-medium text-gray-700">Additional Details</div>
          <div className="space-y-1">
            {Object.entries(additionalFields).map(([key, value]) => (
              <div key={key} className="text-sm">
                <span className="font-medium text-gray-600">{formatFieldName(key)}: </span>
                <span className="text-gray-800">{value}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Context / Call Stack */}
      {context && (
        <div className="space-y-2">
          <button
            onClick={() => setShowContext(!showContext)}
            className="flex items-center gap-1 text-sm font-medium text-gray-500 hover:text-gray-700 transition-colors"
          >
            {showContext ? (
              <ChevronDown className="h-4 w-4" />
            ) : (
              <ChevronRight className="h-4 w-4" />
            )}
            {showContext ? "Hide" : "Show"} Technical Details
            {callStack.length > 0 && (
              <span className="text-gray-400 font-normal">
                ({callStack.length} function{callStack.length !== 1 ? "s" : ""} in call stack)
              </span>
            )}
          </button>

          {showContext && (
            <div className="space-y-3">
              {/* Simplified call stack */}
              {callStack.length > 0 && (
                <div className="p-3 bg-gray-50 border border-gray-200 rounded-md">
                  <div className="text-xs font-medium text-gray-500 mb-2">Call Stack</div>
                  <div className="space-y-1 font-mono text-xs">
                    {callStack.map((func, idx) => (
                      <div key={idx} className="flex items-center gap-2 text-gray-700">
                        <span className="text-gray-400">{idx + 1}.</span>
                        <span>{func}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Full context */}
              <div className="p-3 bg-gray-50 border border-gray-200 rounded-md">
                <div className="text-xs font-medium text-gray-500 mb-2">Full Context</div>
                <pre className="text-xs text-gray-600 whitespace-pre-wrap break-words overflow-auto max-h-48">
                  {context}
                </pre>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export function ErrorBadges({ errors, variant = "errors", className }: ErrorDisplayProps) {
  if (!errors || (typeof errors === "object" && Object.keys(errors).length === 0)) {
    return null;
  }

  // Handle string errors
  if (typeof errors === "string") {
    try {
      errors = JSON.parse(errors);
    } catch {
      return null;
    }
  }

  const entries = Object.entries(errors).filter(([key, value]) => {
    if (key === "context") return false;
    if (value === null || value === undefined || value === "") return false;
    return true;
  });

  if (entries.length === 0) {
    return null;
  }

  const isError = variant === "errors";
  const bgColor = isError ? "bg-red-100" : "bg-amber-100";
  const textColor = isError ? "text-red-700" : "text-amber-700";
  const hoverBg = isError ? "hover:bg-red-200" : "hover:bg-amber-200";

  return (
    <div className={cn("flex flex-wrap gap-1", className)}>
      {entries.map(([field, value]) => (
        <span
          key={field}
          className={cn(
            "text-xs px-1.5 py-0.5 rounded",
            bgColor,
            textColor,
            hoverBg,
            "cursor-help"
          )}
          title={`${formatFieldName(field)}: ${extractMainError(String(value))}`}
        >
          {formatFieldName(field)}
        </span>
      ))}
    </div>
  );
}
