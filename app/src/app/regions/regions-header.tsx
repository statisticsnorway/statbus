"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { List as ListIcon, Map as MapIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";

/**
 * The Regions header, the same on its list and its map (owner 2026-11-23, z2qt08):
 * the title centred, and on the right the button to the other view, alike but for its icon.
 * The map puts its region trail (World › Norway › Trøndelag) on the left. The list offers the
 * map only in coordinates mode with a centre to draw (`mapOffered`, owner 2026-11-26, 5yxn4w);
 * the map always offers the list.
 */
export function RegionsHeader({
  view,
  breadcrumb,
  mapOffered = true,
}: {
  view: "list" | "map";
  breadcrumb?: ReactNode;
  mapOffered?: boolean;
}) {
  const other =
    view === "list"
      ? { href: "/regions/map", label: "Map", Icon: MapIcon, data: { "data-regions-map-link": "" } }
      : { href: "/regions", label: "List", Icon: ListIcon, data: { "data-regions-list-link": "" } };
  return (
    <div className="relative mb-6 flex items-center justify-center lg:mb-12" data-regions-header="">
      {breadcrumb && <div className="absolute left-0 max-w-[35%]">{breadcrumb}</div>}
      <h1 className="text-center text-xl lg:text-2xl">Regions</h1>
      {(view === "map" || mapOffered) && (
        <Link href={other.href} className={`${buttonVariants({ variant: "outline", size: "sm" })} absolute right-0`} {...other.data}>
          <other.Icon className="mr-1.5 h-4 w-4" />
          {other.label}
        </Link>
      )}
    </div>
  );
}
