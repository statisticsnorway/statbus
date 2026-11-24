"use client";

import Link from "next/link";
import { SquareArrowOutUpRight } from "lucide-react";

/**
 * Opens a set of units in the search, as an icon: the same square arrow that opens a unit's page
 * on a unit's Map page (owner 2026-11-24), so leaving the map reads alike on both. Its hover text
 * says which units it opens, as the "View and download" button did. Used where the row has other
 * actions too (a list row picks, its chevron goes in); a row whose only action is this is a
 * SearchRow.
 */
export function OpenInSearch({ href, title, ...rest }: { href: string; title: string } & Record<`data-${string}`, string>) {
  return (
    <Link
      href={href}
      className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
      title={title}
      aria-label={title}
      {...rest}
    >
      <SquareArrowOutUpRight className="h-3.5 w-3.5" />
    </Link>
  );
}

/** The hover text for a place's units: "View and download the units in Vestland". */
export function unitsIn(name: string): string {
  return `View and download the units in ${name}`;
}

/**
 * A row whose only action is opening its units in the search: the whole row is the link, lit on
 * hover, and ends in the square arrow, which says it leaves the map (owner 2026-11-24). The arrows
 * of these rows stand in one column at the right edge.
 */
export function SearchRow({
  href,
  title,
  className = "",
  children,
  ...rest
}: { href: string; title: string; className?: string; children: React.ReactNode } & Record<`data-${string}`, string>) {
  return (
    <Link href={href} title={title} className={`group -mx-1 flex items-center gap-1 rounded px-1 hover:bg-gray-100 ${className}`} {...rest}>
      {children}
      <span className="shrink-0 rounded p-1 text-gray-500 group-hover:text-gray-900" aria-hidden>
        <SquareArrowOutUpRight className="h-3.5 w-3.5" />
      </span>
    </Link>
  );
}
