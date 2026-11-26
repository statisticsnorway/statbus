"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useAtomValue } from "jotai";
import { Map as MapIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { searchResultAtom } from "@/atoms/search";

/**
 * Opens the units of this search on the Reports map (5nq78t), with the same filter: the map counts
 * them by region in the same time frame, and its "View and download" rows come back here. The
 * list's own page and sort order stay behind. It stands beside Download and follows it (owner
 * 2026-11-26): shown once the search has counted its units, in Download's style, and not for a
 * search with none, which has nothing to map.
 */
export function SearchMapLink() {
  const searchResult = useAtomValue(searchResultAtom);
  const searchParams = useSearchParams();
  if (!searchResult?.total) return null;
  const params = new URLSearchParams(searchParams?.toString() ?? "");
  params.delete("page");
  params.delete("order");
  const query = params.toString();
  return (
    <Link
      href={query ? `/reports/map?${query}` : "/reports/map"}
      className={cn(buttonVariants({ variant: "secondary", size: "sm" }), "flex items-center space-x-2")}
      title="Show these units on a map, by region"
      data-search-map-link=""
    >
      <MapIcon size={17} />
      <span>Map</span>
    </Link>
  );
}
