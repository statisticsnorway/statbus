import { createClient } from "@/lib/supabase/server";
import Search from "@/app/search/components/search";
import { Metadata } from "next";
import { createFilters } from "@/app/search/filters";
import { createServerLogger } from "@/lib/server-logger";

export const metadata: Metadata = {
  title: "StatBus | Search statistical units",
};

export default async function SearchPage({
  searchParams,
}: {
  readonly searchParams: URLSearchParams;
}) {
  const client = createClient();
  const logger = await createServerLogger();

  const [
    sectors,
    legalForms,
    regions,
    activityCategories,
    statisticalVariables,
  ] = await Promise.all([
    client.from("sector_used").select().not("code", "is", null),
    client.from("legal_form_used").select().not("code", "is", null),
    client.from("region_used").select(),
    client.from("activity_category_used").select(),
    client
      .from("stat_definition")
      .select()
      .order("priority", { ascending: true }),
  ]);

  if (sectors.error) {
    logger.error(sectors.error, "failed to fetch sectors");
  }

  if (legalForms.error) {
    logger.error(legalForms.error, "failed to fetch legal forms");
  }

  if (regions.error) {
    logger.error(regions.error, "failed to fetch regions");
  }

  if (activityCategories.error) {
    logger.error(
      activityCategories.error,
      "failed to fetch activity categories"
    );
  }

  const urlSearchParams = new URLSearchParams(searchParams);

  const searchFilters = createFilters(
    {
      activityCategories: activityCategories.data ?? [],
      regions: regions.data ?? [],
      statisticalVariables: statisticalVariables.data ?? [],
      sectors: sectors.data ?? [],
      legalForms: legalForms.data ?? [],
    },
    urlSearchParams
  );

  const [orderBy, ...orderDirections] = urlSearchParams
    .get("order")
    ?.split(".") ?? ["name", "asc"];

  const defaultCurrentPage = 1;
  const defaultPageSize = 10;

  const currentPage = Number(urlSearchParams.get("page")) || defaultCurrentPage;

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-24">
      <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
        Search for statistical units
      </h1>
      <Search
        regions={regions.data ?? []}
        activityCategories={activityCategories.data ?? []}
        statisticalVariables={statisticalVariables.data ?? []}
        searchFilters={searchFilters}
        searchOrder={{ name: orderBy, direction: orderDirections.join(".") }}
        searchPagination={{
          pageNumber: currentPage,
          pageSize: defaultPageSize,
        }}
      />
    </main>
  );
}
