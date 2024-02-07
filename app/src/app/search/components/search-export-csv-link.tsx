import {SearchResult} from "@/app/search/search.types";

const MAX_LIMIT_STATISTICAL_UNITS_EXPORT = 10000

export function ExportCSVLink({searchParams, searchResult}: { readonly searchParams: URLSearchParams, readonly searchResult?: SearchResult }) {
    if (!searchResult?.count) return null

    return searchResult.count < MAX_LIMIT_STATISTICAL_UNITS_EXPORT
        ? (
            <a target="_blank" href={`/search/export?${searchParams}`} className="hover:underline">Export as CSV</a>
        ) : (
            <span>Too many rows for CSV export (max {MAX_LIMIT_STATISTICAL_UNITS_EXPORT})</span>
        )
}
