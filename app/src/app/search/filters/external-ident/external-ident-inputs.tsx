"use client";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSearch } from "@/atoms/hooks"; // Changed to Jotai hook
import { useCallback, useEffect, useState } from "react";
import { Tables } from "@/lib/database.types";
// import { externalIdentDeriveStateUpdateFromValues } from "../url-search-params"; // Removed
import { Button } from "@/components/ui/button";

export function ExternalIdentInputs({
  externalIdentTypes
}: {
  readonly externalIdentTypes: Tables<"external_ident_type_ordered">[];
}) {
  const { searchState, updateFilters, executeSearch } = useSearch();
  const { filters } = searchState;

  // Create a state object to track debounced values for each input
  const [debouncedValues, setDebouncedValues] = useState<Record<string, string>>(() =>
    externalIdentTypes.reduce((acc, type) => {
      const filterValue = filters[type.code!];
      acc[type.code!] = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || '';
      return acc;
    }, {} as Record<string, string>)
  );

  // Effect to synchronize debouncedValues if external filters change (e.g., from URL or reset)
  useEffect(() => {
    setDebouncedValues(
      externalIdentTypes.reduce((acc, type) => {
        const filterValue = filters[type.code!];
        acc[type.code!] = (Array.isArray(filterValue) ? filterValue[0] : filterValue) || '';
        return acc;
      }, {} as Record<string, string>)
    );
  }, [filters, externalIdentTypes]);

  const updateIdentifier = useCallback(async (identType: Tables<"external_ident_type_ordered">, value: string) => {
    const newFilters = { ...filters };
    if (value && value.trim() !== '') {
      newFilters[identType.code!] = value;
    } else {
      delete newFilters[identType.code!];
    }
    updateFilters(newFilters);
    await executeSearch();
  }, [filters, updateFilters, executeSearch]);

  // Add reset function to clear all external identifier inputs
  const reset = useCallback(async () => {
    const newFilters = { ...filters };
    externalIdentTypes.forEach(identType => {
      delete newFilters[identType.code!];
    });
    updateFilters(newFilters);
    // Debounced values will be cleared by the useEffect listening to filters
    await executeSearch();
  }, [filters, externalIdentTypes, updateFilters, executeSearch]);

  // Add debounce effect for each input
  useEffect(() => {
    const handlers = externalIdentTypes.map(identType => {
      const handler = setTimeout(() => {
        const value = debouncedValues[identType.code!];
        updateIdentifier(identType, value);
      }, 300); // 300ms delay, same as full text search

      return () => clearTimeout(handler);
    });

    return () => handlers.forEach(cleanup => cleanup());
  }, [debouncedValues, externalIdentTypes, updateIdentifier]);

  // Check if any identifier has a value
  const hasValues = Object.values(debouncedValues).some(value => value !== '');

  return (
    <div className="grid gap-4">
      {externalIdentTypes.map((identType) => {
        return (
          <div key={identType.code} className="grid gap-2">
            <Label htmlFor={identType.code!}>{identType.name}</Label>
            <Input
              id={identType.code!}
              placeholder={`Search by ${identType.name}`}
              value={debouncedValues[identType.code!]}
              onChange={(e) => setDebouncedValues(prev => ({
                ...prev,
                [identType.code!]: e.target.value
              }))}
            />
          </div>
        );
      })}
      {hasValues && (
        <Button onClick={reset} variant="outline" className="w-full">
          Clear
        </Button>
      )}
    </div>
  );
}
