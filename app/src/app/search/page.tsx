export const dynamic = 'force-dynamic';

import { Metadata } from "next";
import { getServerRestClient } from "@/context/RestClientStore";
import { toURLSearchParams, URLSearchParamsDict } from "@/lib/url-search-params-dict";
import SearchPageClient from "./SearchPageClient";

export const metadata: Metadata = {
  title: "Search statistical units",
};

export default async function SearchPage(props: { searchParams: Promise<URLSearchParamsDict> }) {
  const initialUrlSearchParamsDict = await props.searchParams;
  const initialUrlSearchParams = toURLSearchParams(initialUrlSearchParamsDict);
  initialUrlSearchParams.sort();
  const initialUrlSearchParamsString = initialUrlSearchParams.toString();

  const client = await getServerRestClient();
  // Note: Lookup data (regions, activity categories, etc.) is now fetched client-side
  // via fetchSearchPageDataAtom to avoid RSC hydration timing issues.
  // The props are still passed for backwards compatibility but may be empty during hydration.
  const [
    { data: activityCategories },
    { data: regions },
    { data: statuses },
    { data: unitSizes },
    { data: dataSources },
    { data: externalIdentTypes },
    { data: legalForms },
    { data: sectors },
  ] = await Promise.all([
    client.from("activity_category_used").select(),
    client.from("region_used").select(),
    client.from("status").select().filter("enabled", "eq", true),
    client.from("unit_size").select().filter("enabled", "eq", true),
    client.from("data_source_used").select(),
    client.from("external_ident_type_active").select(),
    client.from("legal_form_used").select().not("code", "is", null),
    client.from("sector_used").select(),
  ]);

  return (
    <SearchPageClient
      allRegions={regions ?? []}
      allActivityCategories={activityCategories ?? []}
      allStatuses={statuses ?? []}
      allUnitSizes={unitSizes ?? []}
      allDataSources={dataSources ?? []}
      allExternalIdentTypes={externalIdentTypes ?? []}
      allLegalForms={legalForms ?? []}
      allSectors={sectors ?? []}
      initialUrlSearchParamsString={initialUrlSearchParamsString}
    />
  );
}
