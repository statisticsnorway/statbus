"use client";
import Link from "next/link";
import { ReactNode, useState } from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { STATUS, UNIT_TYPE } from "@/app/search/filters/url-search-params";

/**
 * The Statistical Units list a unit count card links to. The card counts the
 * units whose status is used for counting (statistical_unit.used_for_counting,
 * see StatisticalUnitCountCard), so the link selects those statuses: the list
 * shows the units the card counts and the Status chip says which statuses
 * those are. Statuses are defined per installation, so the codes come from the
 * enabled statuses with used_for_counting.
 */
export function countedUnitsHref(
  unitType: string,
  countingStatusCodes: string[]
): string {
  const params = new URLSearchParams({ [UNIT_TYPE]: unitType });
  if (countingStatusCodes.length > 0) {
    params.set(STATUS, countingStatusCodes.join(","));
  }
  return `/search?${params.toString().replace(/%2C/g, ",")}`;
}

export const CountedUnitsLink = ({
  unitType,
  children,
}: {
  readonly unitType: "enterprise" | "legal_unit" | "establishment";
  readonly children: ReactNode;
}) => {
  const [countingStatusCodes, setCountingStatusCodes] = useState<string[]>([]);

  useGuardedEffect(
    () => {
      getBrowserRestClient()
        .then((client) =>
          client
            .from("status_enabled")
            .select("code")
            .eq("used_for_counting", true)
            .order("priority")
        )
        .then(({ data }) =>
          setCountingStatusCodes(
            (data ?? []).flatMap(({ code }) => (code ? [code] : []))
          )
        );
    },
    [],
    "CountedUnitsLink:fetchCountingStatuses"
  );

  return (
    <Link href={countedUnitsHref(unitType, countingStatusCodes)}>
      {children}
    </Link>
  );
};
