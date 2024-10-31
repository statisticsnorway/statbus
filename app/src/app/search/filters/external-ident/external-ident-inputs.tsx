"use client";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { Tables } from "@/lib/database.types";
import { externalIdentDeriveStateUpdateFromValues } from "../url-search-params";

export function ExternalIdentInputs({ 
  externalIdentTypes 
}: {
  readonly externalIdentTypes: Tables<"external_ident_type_ordered">[];
}) {
  const { modifySearchState, searchState } = useSearchContext();

  const updateIdentifier = useCallback((identType: Tables<"external_ident_type_ordered">, value: string) => {
    modifySearchState(
      externalIdentDeriveStateUpdateFromValues(identType, value || null)
    );
  }, [modifySearchState]);

  return (
    <div className="grid gap-4">
      {externalIdentTypes.map((identType) => {
        const selected = searchState.appSearchParams[identType.code!] ?? [];
        return (
          <div key={identType.code} className="grid gap-2">
            <Label htmlFor={identType.code}>{identType.name}</Label>
            <Input
              id={identType.code}
              placeholder={`Search by ${identType.name}`}
              value={selected[0] ?? ""}
              onChange={(e) => updateIdentifier(identType, e.target.value)}
            />
          </div>
        );
      })}
    </div>
  );
}
