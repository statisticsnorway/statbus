import { createSupabaseSSRClient } from "@/utils/supabase/server";
import RegionOptions from "@/app/search/filters/region/region-options";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default async function RegionFilter({ urlSearchParam }: IProps) {
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
        urlSearchParam
          ?.split(",")
          .map((value) => (value === "null" ? null : value)) ?? []
      }
    />
  );
}
