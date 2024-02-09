import {SearchResult} from "@/app/search/search.types";
import Link from "next/link";
import {buttonVariants} from "@/components/ui/button";
import {Download} from "lucide-react";
import {cn} from "@/lib/utils";

const MAX_LIMIT_STATISTICAL_UNITS_EXPORT = 10000

export function ExportCSVLink({searchParams, searchResult}: {
  readonly searchParams: URLSearchParams,
  readonly searchResult?: SearchResult
}) {
  if (!searchResult?.count || searchResult.count > MAX_LIMIT_STATISTICAL_UNITS_EXPORT) return null

  return (
    <Link
      target="_blank"
      href={`/search/export?${searchParams}`}
      className={cn(buttonVariants({variant: "secondary", size: "sm"}), "flex items-center space-x-2")}
    >
      <Download size={17}/>
      <span>Export as CSV</span>
    </Link>
  )
}
