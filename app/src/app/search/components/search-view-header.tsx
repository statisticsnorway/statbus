"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import { List as ListIcon, Map as MapIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";

/**
 * The search's header, the same on its list and its map (5nq78t, owner 2026-11-26): the title
 * centred, and at the right edge the button to the other view, alike but for its icon, as on the
 * Regions list and map. The two views are one search: the switch keeps the whole query. The map
 * ignores the list's sort order and page (it counts by region; owner 2026-11-26: ordering is
 * inconsequential to a map) and carries them along, so List comes back as it was left. The map
 * puts its region trail on the left.
 */
export function SearchViewHeader({
  view,
  breadcrumb,
}: {
  view: "list" | "map";
  breadcrumb?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const query = searchParams?.toString() ?? "";
  const other =
    view === "list"
      ? {
          href: query ? `/search/map?${query}` : "/search/map",
          label: "Map",
          Icon: MapIcon,
          data: { "data-search-map-link": "" },
        }
      : {
          href: query ? `/search?${query}` : "/search",
          label: "List",
          Icon: ListIcon,
          data: { "data-search-list-link": "" },
        };
  return (
    <div
      className="relative mb-6 flex items-center justify-center lg:mb-12"
      data-search-header=""
    >
      {breadcrumb && (
        <div className="absolute left-0 max-w-[35%]">{breadcrumb}</div>
      )}
      <h1 className="text-center text-xl lg:text-2xl">
        Search for statistical units
      </h1>
      <Link
        href={other.href}
        className={`${buttonVariants({ variant: "outline", size: "sm" })} absolute right-0`}
        title={
          view === "list"
            ? "Show these units on a map, by region"
            : "Show these units as a list"
        }
        {...other.data}
      >
        <other.Icon className="mr-1.5 h-4 w-4" />
        {other.label}
      </Link>
    </div>
  );
}
