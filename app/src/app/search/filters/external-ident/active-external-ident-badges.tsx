"use client";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { useSearchFilters } from "@/atoms/search";
import { Tables } from "@/lib/database.types";

interface ActiveExternalIdentBadgesProps {
  readonly externalIdentTypes: Tables<"external_ident_type_ordered">[];
}

export function ActiveExternalIdentBadges({ externalIdentTypes }: ActiveExternalIdentBadgesProps) {
  const { filters } = useSearchFilters();

  const activeFilters = externalIdentTypes
    .map(type => {
      const filterValue = filters[type.code!];
      // Assuming filterValue is a string or an array of strings.
      // If it's an array, take the first element. If string, take the string.
      // Ensure it's a non-empty string to be considered active.
      const displayValue = Array.isArray(filterValue) ? filterValue[0] : filterValue;
      if (displayValue && String(displayValue).length > 0) {
        return {
          code: type.code,
          value: String(displayValue) // Ensure it's a string for display
        };
      }
      return null;
    })
    .filter(Boolean) as { code: string; value: string }[]; // Type assertion after filtering nulls

  if (activeFilters.length === 0) return null;

  return (
    <>
      <Separator orientation="vertical" className="h-1/2" />
      {activeFilters.map(({ code, value }) => (
        <Badge
          key={code}
          variant="secondary"
          className="rounded-sm px-2 font-normal max-w-32 overflow-hidden text-ellipsis"
          title={`${code}: ${value}`}
        >
          {code}: {value}
        </Badge>
      ))}
    </>
  );
}
