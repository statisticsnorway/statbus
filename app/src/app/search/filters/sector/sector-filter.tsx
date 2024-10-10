import { createSupabaseSSRClient } from "@/utils/supabase/server";
import SectorOptions from "@/app/search/filters/sector/sector-options";
import { SECTOR } from "../url-search-params";
import { IURLSearchParamsDict, toURLSearchParams } from "@/lib/url-search-params-dict";

export default async function SectorFilter({ initialUrlSearchParamsDict: initialUrlSearchParams }: IURLSearchParamsDict) {
  const urlSearchParams = toURLSearchParams(initialUrlSearchParams);

  const sector = urlSearchParams.get(SECTOR);
  const client = await createSupabaseSSRClient();
  const sectors = await client.from("sector_used").select();

  return (
    <SectorOptions
      options={
        sectors.data?.map(({ code, path, name }) => ({
          label: code ? `${code} ${name}` : `${name}`,
          value: path as string,
          humanReadableValue: code ? `${code} ${name}` : `${name}`,
        })) ?? []
      }
      selected={sector ? sector.split(",") : []}
    />
  );
}
