"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Map as MapIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";

/**
 * Opens the units of this search on the Reports map (5nq78t), with the same filter: the map counts
 * them by region in the same time frame, and its "View and download" rows come back here. The
 * list's own page and sort order stay behind.
 */
export function SearchMapLink() {
  const searchParams = useSearchParams();
  const params = new URLSearchParams(searchParams?.toString() ?? "");
  params.delete("page");
  params.delete("order");
  const query = params.toString();
  return (
    <Link
      href={query ? `/reports/map?${query}` : "/reports/map"}
      className={buttonVariants({ variant: "outline", size: "sm" })}
      title="Show these units on a map, by region"
      data-search-map-link=""
    >
      <MapIcon className="mr-1.5 h-4 w-4" />
      Map
    </Link>
  );
}
