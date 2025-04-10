"use server";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import RegionOptions from "@/app/search/filters/region/region-options";

export default async function RegionFilter() {
  const client = await createPostgRESTSSRClient();
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
    />
  );
}
