"use client";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSearchParams, useRouter } from "next/navigation";
import { TableResultCount } from "@/components/table/table-result-count";
import ActivityCategoryTable from "./activity-category-table";
import TablePagination from "@/components/table/table-pagination";
import useActivityCategories from "./use-activity-categories";
import TableFilters from "./activity-category-table-filters";
export default function ActivityCategoryPage() {
  const { data, pagination, setPagination, queries, setQueries } =
    useActivityCategories();
  const searchParams = useSearchParams();
  const router = useRouter();

  useGuardedEffect(() => {
    const customParam = searchParams.get("custom");
    if (customParam === "true" || customParam === "false") {
      setQueries((prev) => ({ ...prev, custom: customParam === "true" }));
      const newParams = new URLSearchParams(searchParams.toString());
      newParams.delete("custom");
      router.replace(`/activity-categories?${newParams.toString()}`);
    }
  }, [searchParams, setQueries, router]);

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
        Activity Categories
      </h1>
      <section className="space-y-3">
        <TableFilters
          setQueries={setQueries}
          setPagination={setPagination}
          queries={queries}
        />
        <div className="rounded-md border overflow-hidden">
          <ActivityCategoryTable
            activityCategories={data?.activityCategories ?? []}
          />
        </div>
        <div className="lg:grid lg:grid-cols-3 items-center justify-center text-xs text-gray-500">
          <TableResultCount
            pagination={pagination}
            total={data?.count ?? 0}
            className="hidden lg:inline-block"
          />
          <TablePagination
            pagination={pagination}
            setPagination={setPagination}
            total={data?.count ?? 0}
          />
        </div>
      </section>
    </main>
  );
}
