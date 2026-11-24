"use client";

import Link from "next/link";
import { SquareArrowOutUpRight } from "lucide-react";

/**
 * Opens a place's units in the search, as an icon: the same square arrow that opens a unit's page
 * on a unit's Map page (owner 2026-11-24), so leaving the map reads alike on both. The title says
 * where it goes, as the "View and download" button did.
 */
export function OpenInSearch({ href, name, ...rest }: { href: string; name: string } & Record<`data-${string}`, string>) {
  return (
    <Link
      href={href}
      className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
      title={`View and download the units in ${name}`}
      aria-label={`View and download the units in ${name}`}
      {...rest}
    >
      <SquareArrowOutUpRight className="h-3.5 w-3.5" />
    </Link>
  );
}
