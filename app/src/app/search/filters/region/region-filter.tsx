import { createClient } from "@/lib/supabase/server";
import RegionOptions from "@/app/search/filters/region/region-options";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default async function RegionFilter({ urlSearchParam: param }: IProps) {
  const client = createClient();
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
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`,
        })) ?? []),
      ]}
      selected={param ? [param] : []}
    />
  );
}
