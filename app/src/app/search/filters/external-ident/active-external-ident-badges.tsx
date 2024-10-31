"use client";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { useSearchContext } from "@/app/search/use-search-context";
import { Tables } from "@/lib/database.types";

interface ActiveExternalIdentBadgesProps {
  readonly externalIdentTypes: Tables<"external_ident_type_ordered">[];
}

export function ActiveExternalIdentBadges({ externalIdentTypes }: ActiveExternalIdentBadgesProps) {
  const { searchState: { appSearchParams } } = useSearchContext();

  const activeFilters = externalIdentTypes
    .filter(type => (appSearchParams[type.code!]?.length ?? 0) > 0)
    .map(type => ({
      code: type.code,
      value: appSearchParams[type.code!]?.[0]
    }));

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
