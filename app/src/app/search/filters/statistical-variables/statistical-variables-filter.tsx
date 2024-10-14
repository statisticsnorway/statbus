import { createSupabaseSSRClient } from "@/utils/supabase/server";
import StatisticalVariablesOptions from "@/app/search/filters/statistical-variables/statistical-variables-options";

export default async function StatisticalVariablesFilter() {
  const client = await createSupabaseSSRClient();
  const statDefinitions = await client
    .from("stat_definition_ordered")
    .select();

  return (
    <>
      {statDefinitions.data?.map((statDefinition) => {
        return (
          <StatisticalVariablesOptions
            key={"stat_var"+statDefinition.code!}
            statDefinition={statDefinition}
            />
        );
      })}
    </>
  );
}

