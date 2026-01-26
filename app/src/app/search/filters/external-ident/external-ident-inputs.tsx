"use client";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useState, useMemo } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { Tables } from "@/lib/database.types";
import { Button } from "@/components/ui/button";
import { HierarchicalIdentInputs } from "./hierarchical-ident-inputs";

export function ExternalIdentInputs({
  externalIdentTypes
}: {
  readonly externalIdentTypes: Tables<"external_ident_type_ordered">[];
}) {
  const { filters, updateFilters } = useSearchFilters();

  // Separate regular and hierarchical identifier types
  const { regularTypes, hierarchicalTypes } = useMemo(() => {
    const regular: Tables<"external_ident_type_ordered">[] = [];
    const hierarchical: Tables<"external_ident_type_ordered">[] = [];
    
    for (const type of externalIdentTypes) {
      if (type.shape === "hierarchical") {
        hierarchical.push(type);
      } else {
        regular.push(type);
      }
    }
    
    return { regularTypes: regular, hierarchicalTypes: hierarchical };
  }, [externalIdentTypes]);

  // Create a state object to track debounced values for regular inputs only
  const [debouncedValues, setDebouncedValues] = useState<Record<string, string>>(() =>
    regularTypes.reduce((acc, type) => {
      const filterValue = filters[type.code!];
      acc[type.code!] = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || '';
      return acc;
    }, {} as Record<string, string>)
  );

  // Effect to synchronize debouncedValues if external filters change (e.g., from URL or reset)
  useGuardedEffect(() => {
    setDebouncedValues(
      regularTypes.reduce((acc, type) => {
        const filterValue = filters[type.code!];
        acc[type.code!] = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || '';
        return acc;
      }, {} as Record<string, string>)
    );
  }, [filters, regularTypes], 'ExternalIdentInputs:syncDebouncedValues');

  const updateIdentifier = useCallback(async (identType: Tables<"external_ident_type_ordered">, localValue: string) => {
    const code = identType.code!;
    // Get the current value from global state (searchState.filters)
    // Ensure consistent handling: if filters[code] is an array, take first, otherwise take as is. Default to undefined.
    const globalFilterEntry = filters[code];
    const currentGlobalFilterValue = (Array.isArray(globalFilterEntry) ? globalFilterEntry[0] : globalFilterEntry) as string | undefined;

    const trimmedLocalValue = localValue.trim(); // Value from the input field, after debounce

    let needsUpdate = false;

    if (trimmedLocalValue !== '') { // User wants to set a non-empty value
      if (currentGlobalFilterValue !== trimmedLocalValue) {
        needsUpdate = true;
      }
    } else { // User wants to clear the value (trimmedLocalValue is empty)
      // Only needs update if there was a non-empty value before in global state
      if (filters.hasOwnProperty(code) && currentGlobalFilterValue && currentGlobalFilterValue.trim() !== '') {
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      const newFilters = { ...filters };
      if (trimmedLocalValue !== '') {
        newFilters[code] = trimmedLocalValue;
      } else {
        delete newFilters[code];
      }
      updateFilters(newFilters);
    }
  }, [filters, updateFilters]);

  // Add reset function to clear all external identifier inputs
  const reset = useCallback(async () => {
    const newFilters = { ...filters };
    externalIdentTypes.forEach(identType => {
      delete newFilters[identType.code!];
    });
    updateFilters(newFilters);
    // Debounced values will be cleared by the useEffect listening to filters
  }, [filters, externalIdentTypes, updateFilters]);

  // Add debounce effect for regular inputs only
  useGuardedEffect(() => {
    const handlers = regularTypes.map(identType => {
      const handler = setTimeout(() => {
        const value = debouncedValues[identType.code!];
        updateIdentifier(identType, value);
      }, 300); // 300ms delay, same as full text search

      return () => clearTimeout(handler);
    });

    return () => handlers.forEach(cleanup => cleanup());
  }, [debouncedValues, regularTypes, updateIdentifier], 'ExternalIdentInputs:debounceEffect');

  // Check if any identifier has a value (both regular and hierarchical)
  const hasRegularValues = Object.values(debouncedValues).some(value => value !== '');
  const hasHierarchicalValues = hierarchicalTypes.some(type => {
    const filterValue = filters[type.code!];
    const value = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || '';
    return value !== '';
  });
  const hasValues = hasRegularValues || hasHierarchicalValues;

  return (
    <div className="grid gap-4">
      {/* Regular identifier inputs */}
      {regularTypes.map((identType) => {
        return (
          <div key={identType.code} className="grid gap-2">
            <Label htmlFor={identType.code!}>{identType.name}</Label>
            <Input
              id={identType.code!}
              placeholder={`Search by ${identType.name}`}
              value={debouncedValues[identType.code!] || ''}
              onChange={(e) => setDebouncedValues(prev => ({
                ...prev,
                [identType.code!]: e.target.value
              }))}
            />
          </div>
        );
      })}
      
      {/* Hierarchical identifier inputs */}
      {hierarchicalTypes.map((identType) => (
        <HierarchicalIdentInputs key={identType.code} identType={identType} />
      ))}
      
      {hasValues && (
        <Button onClick={reset} variant="outline" className="w-full">
          Clear
        </Button>
      )}
    </div>
  );
}
