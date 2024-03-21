import { createClient } from "@/lib/supabase/server";
import Search from "@/app/search/components/search";
import { Metadata } from "next";
import { createFilters } from "@/app/search/filters";
import { createServerLogger } from "@/lib/logger";

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

  const sectorPromise = client
    .from("sector_used")
    .select()
    .not("code", "is", null);

  const legalFormPromise = client
    .from("legal_form_used")
    .select()
    .not("code", "is", null);

  const regionPromise = client.from("region_used").select();

  const activityCategoryPromise = client
    .from("activity_category_used")
    .select();

  const statDefinitionPromise = client
    .from("stat_definition")
    .select()
    .order("priority", { ascending: true });

  const [
    { data: sectors, error: sectorsError },
    { data: legalForms, error: legalFormsError },
    { data: regions, error: regionsError },
    { data: activityCategories, error: activityCategoriesError },
    { data: statisticalVariables },
  ] = await Promise.all([
    sectorPromise,
    legalFormPromise,
    regionPromise,
    activityCategoryPromise,
    statDefinitionPromise,
  ]);

  if (sectorsError) {
    logger.error(sectorsError, "failed to fetch sectors");
  }

  if (legalFormsError) {
    logger.error(legalFormsError, "failed to fetch legal forms");
  }

  if (regionsError) {
    logger.error(regionsError, "failed to fetch regions");
  }

  if (activityCategoriesError) {
    logger.error(
      activityCategoriesError,
      "failed to fetch activity categories"
    );
  }

  const urlSearchParams = new URLSearchParams(searchParams);

  const searchFilters = createFilters(
    {
      activityCategories: activityCategories ?? [],
      regions: regions ?? [],
      statisticalVariables: statisticalVariables ?? [],
      sectors: sectors ?? [],
      legalForms: legalForms ?? [],
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
        regions={regions ?? []}
        activityCategories={activityCategories ?? []}
        statisticalVariables={statisticalVariables ?? []}
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
