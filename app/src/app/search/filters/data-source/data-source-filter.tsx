import { createSupabaseSSRClient } from "@/utils/supabase/server";
import DataSourceOptions from "@/app/search/filters/data-source/data-source-options";

export default async function DataSourceFilter() {
  const client = await createSupabaseSSRClient();
  const {data: dataSources} = await client.from("data_source_used").select();

  return (
    <DataSourceOptions
      dataSources={dataSources ?? []}
      options={
        dataSources?.map(({ code, name }) => ({
          label: name,
          value: code,
          humanReadableValue: name,
        })) ?? []
      }
    />
  );
}
