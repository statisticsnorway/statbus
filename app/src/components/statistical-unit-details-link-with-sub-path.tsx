"use client";

import { usePathname, useSearchParams } from "next/navigation";
import {
  StatisticalUnitDetailsLink,
  StatisticalUnitDetailsLinkProps,
} from "@/components/statistical-unit-details-link";

export function StatisticalUnitDetailsLinkWithSubPath(
  props: StatisticalUnitDetailsLinkProps
) {
  /* When navigating between units, we want to keep the path the same.
   * For example, if we are on /legal-units/1/contact, and we click on an establishment,
   * we want to go to /establishments/2/contact. */

  const pathname = usePathname();
  const params = useSearchParams().toString();
  const path = pathname.split(/\d{1,10}\//)?.[1] ?? "";

  return (
    <StatisticalUnitDetailsLink {...props} sub_path={path} params={params} />
  );
}
