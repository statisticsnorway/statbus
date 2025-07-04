"use client";
import { cn } from "@/lib/utils";
import { useAtomValue } from 'jotai';
import { searchStateAtom, searchResultAtom } from '@/atoms/search';

export const SearchResultCount = ({
  className,
}: {
  readonly className?: string;
}) => {
  const searchState = useAtomValue(searchStateAtom);
  const searchResult = useAtomValue(searchResultAtom);
  const { pagination } = searchState;

  const hasResults = searchResult?.total;
  const startIndex = hasResults
    ? (pagination.page - 1) * pagination.pageSize + 1
    : 0;
  const endIndex = hasResults
    ? Math.min(pagination.page * pagination.pageSize, searchResult.total)
    : 0;
  return (
    <span className={cn("indent-2.5", className)}>
      Showing {startIndex}-{endIndex} of total {searchResult?.total} results
    </span>
  );
};
