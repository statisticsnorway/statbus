"use server";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import RegionOptions from "@/app/search/filters/region/region-options";
import { REGION } from "../url-search-params";
import { IURLSearchParamsDict, toURLSearchParams } from "@/lib/url-search-params-dict";

export default async function RegionFilter({ initialUrlSearchParamsDict }: IURLSearchParamsDict) {
  const initialUrlSearchParams = toURLSearchParams(initialUrlSearchParamsDict);

  const regionQueryValue = initialUrlSearchParams.get(REGION);
  const client = await createSupabaseSSRClient();
  const regions = await client.from("region_used").select();

  return (
    <RegionOptions
      options={[
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...(regions.data?.map(({ code, path, name }) => ({
          label: code ? `${code} ${name}` : `${name}`,
          value: path as string,
          humanReadableValue: code ? `${code} ${name}` : `${name}`,
        })) ?? []),
      ]}
      selected={
        regionQueryValue
          ?.split(",")
          .map((value) => (value === "null" ? null : value)) ?? []
      }
    />
  );
}
