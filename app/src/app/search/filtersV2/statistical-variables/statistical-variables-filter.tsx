import { createClient } from "@/lib/supabase/server";
import StatisticalVariablesOptions from "@/app/search/filtersV2/statistical-variables/statistical-variables-options";

export default async function StatisticalVariablesFilter() {
  const client = createClient();
  const statisticalVariables = await client
    .from("stat_definition")
    .select()
    .order("priority", { ascending: true });

  // TODO: pass url search params to Child Component

  return (
    <>
      {statisticalVariables.data?.map(({ code, name }) => (
        <StatisticalVariablesOptions key={code} label={name} code={code} />
      ))}
    </>
  );
}
