"use client";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect, useState } from "react";
import { Tables } from "@/lib/database.types";
import { externalIdentDeriveStateUpdateFromValues } from "../url-search-params";

export function ExternalIdentInputs({ 
  externalIdentTypes 
}: {
  readonly externalIdentTypes: Tables<"external_ident_type_ordered">[];
}) {
  const { modifySearchState, searchState } = useSearchContext();

  // Create a state object to track debounced values for each input
  const [debouncedValues, setDebouncedValues] = useState<Record<string, string>>(
    externalIdentTypes.reduce((acc, type) => ({
      ...acc,
      [type.code!]: searchState.appSearchParams[type.code!]?.[0] ?? ''
    }), {})
  );

  const updateIdentifier = useCallback((identType: Tables<"external_ident_type_ordered">, value: string) => {
    modifySearchState(
      externalIdentDeriveStateUpdateFromValues(identType, value || null)
    );
  }, [modifySearchState]);

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

  return (
    <div className="grid gap-4">
      {externalIdentTypes.map((identType) => {
        return (
          <div key={identType.code} className="grid gap-2">
            <Label htmlFor={identType.code}>{identType.name}</Label>
            <Input
              id={identType.code}
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
    </div>
  );
}
