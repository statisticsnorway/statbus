"use client";
import { ResetFilterButton } from "@/app/search/components/reset-filter-button";
import { useSearchContext } from "@/app/search/use-search-context";

export default function TableToolbar() {
  const {
    search: { queries },
    dispatch,
  } = useSearchContext();

  const hasAnyFilterSelected = Object.keys(queries).length > 0;

  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      {hasAnyFilterSelected && (
        <ResetFilterButton
          className="h-9 p-2"
          onReset={() => dispatch({ type: "reset_all" })}
        />
      )}
    </div>
  );
}
