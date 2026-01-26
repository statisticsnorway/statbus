"use client";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useState, useMemo } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { Tables } from "@/lib/database.types";

/**
 * Parse labels ltree (e.g., "census.region.surveyor.unit_no") into an array of level labels.
 */
function parseLabels(labels: unknown): string[] {
  if (typeof labels === "string") {
    return labels.split(".");
  }
  return [];
}

/**
 * Compose individual level values into an ltree-like pattern for search.
 * Empty levels become wildcards (*), trailing wildcards are trimmed.
 * 
 * Examples:
 * - ["CENSUS2024", "CENTRAL", "", ""] => "CENSUS2024.CENTRAL.*" (partial match, needs trailing wildcard)
 * - ["CENSUS2024", "", "OKELLO", ""] => "CENSUS2024.*.OKELLO.*" (partial match)
 * - ["", "CENTRAL", "", ""] => "*.CENTRAL.*" (partial match)
 * - ["", "", "", "102"] => "*.*.*.102" (last level filled, no trailing wildcard needed)
 * - ["CENSUS2024", "CENTRAL", "OKELLO", "102"] => "CENSUS2024.CENTRAL.OKELLO.102" (exact match)
 * - ["", "", "", ""] => "" (all empty = no filter)
 */
function composeSearchPattern(values: string[]): string {
  // Replace empty values with wildcard
  const patternParts = values.map((v) => (v.trim() === "" ? "*" : v.trim()));

  // Find the last non-wildcard position
  let lastNonWildcard = patternParts.length - 1;
  while (lastNonWildcard >= 0 && patternParts[lastNonWildcard] === "*") {
    lastNonWildcard--;
  }

  // If all wildcards, return empty (no filter)
  if (lastNonWildcard < 0) {
    return "";
  }

  // Build the pattern up to the last non-wildcard
  const trimmedPattern = patternParts.slice(0, lastNonWildcard + 1).join(".");
  
  // Only add trailing wildcard if there are more levels after the last filled value
  // This allows partial matching on intermediate levels
  const isLastLevelFilled = lastNonWildcard === patternParts.length - 1;
  
  if (isLastLevelFilled) {
    // Last level is filled - no trailing wildcard needed (exact match on last segment)
    return trimmedPattern;
  } else {
    // Intermediate level - add trailing wildcard for partial matching
    return trimmedPattern + ".*";
  }
}

/**
 * Parse a search pattern back into individual level values.
 * 
 * Examples:
 * - "CENSUS2024.CENTRAL.*" => ["CENSUS2024", "CENTRAL", "", ""]
 * - "CENSUS2024.*.OKELLO.*" => ["CENSUS2024", "", "OKELLO", ""]
 */
function parseSearchPattern(pattern: string, levelCount: number): string[] {
  const result = new Array(levelCount).fill("");
  if (!pattern) return result;

  // Remove trailing .* for parsing
  const cleanPattern = pattern.replace(/\.\*$/, "");
  const parts = cleanPattern.split(".");

  for (let i = 0; i < Math.min(parts.length, levelCount); i++) {
    // Convert wildcard back to empty string
    result[i] = parts[i] === "*" ? "" : parts[i];
  }

  return result;
}

interface HierarchicalIdentInputsProps {
  readonly identType: Tables<"external_ident_type_ordered">;
}

export function HierarchicalIdentInputs({ identType }: HierarchicalIdentInputsProps) {
  const { filters, updateFilters } = useSearchFilters();
  const code = identType.code!;

  // Parse the level labels from the identifier type
  const levelLabels = useMemo(() => parseLabels(identType.labels), [identType.labels]);

  // Initialize level values from the current filter
  const [levelValues, setLevelValues] = useState<string[]>(() => {
    const filterValue = filters[code];
    const pattern = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || "";
    return parseSearchPattern(pattern as string, levelLabels.length);
  });

  // Sync levelValues when external filters change (e.g., from URL or reset)
  useGuardedEffect(() => {
    const filterValue = filters[code];
    const pattern = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || "";
    const newValues = parseSearchPattern(pattern as string, levelLabels.length);
    setLevelValues(newValues);
  }, [filters, code, levelLabels.length], "HierarchicalIdentInputs:syncLevelValues");

  // Debounced update to global filters
  useGuardedEffect(() => {
    const handler = setTimeout(() => {
      const searchPattern = composeSearchPattern(levelValues);
      const currentFilterValue = filters[code];
      const currentPattern = (Array.isArray(currentFilterValue) ? currentFilterValue[0] : currentFilterValue) || "";

      // Only update if the pattern has changed
      if (searchPattern !== currentPattern) {
        const newFilters = { ...filters };
        if (searchPattern) {
          newFilters[code] = searchPattern;
        } else {
          delete newFilters[code];
        }
        updateFilters(newFilters);
      }
    }, 300);

    return () => clearTimeout(handler);
  }, [levelValues, code, filters, updateFilters], "HierarchicalIdentInputs:debounceUpdate");

  const handleLevelChange = useCallback((index: number, value: string) => {
    setLevelValues((prev) => {
      const newValues = [...prev];
      newValues[index] = value;
      return newValues;
    });
  }, []);

  // Capitalize the label for display (e.g., "census" => "Census")
  const formatLabel = (label: string) => label.charAt(0).toUpperCase() + label.slice(1).replace(/_/g, " ");

  return (
    <div className="grid gap-2">
      <Label className="font-medium">{identType.name}</Label>
      <div className="grid grid-cols-2 gap-2">
        {levelLabels.map((label, index) => (
          <div key={`${code}-${label}`} className="grid gap-1">
            <Label htmlFor={`${code}-${index}`} className="text-xs text-muted-foreground">
              {formatLabel(label)}
            </Label>
            <Input
              id={`${code}-${index}`}
              placeholder={formatLabel(label)}
              value={levelValues[index] || ""}
              onChange={(e) => handleLevelChange(index, e.target.value)}
              className="h-8 text-sm"
            />
          </div>
        ))}
      </div>
    </div>
  );
}
