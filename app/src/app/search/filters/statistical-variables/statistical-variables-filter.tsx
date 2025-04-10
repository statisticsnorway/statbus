import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import StatisticalVariablesOptions from "@/app/search/filters/statistical-variables/statistical-variables-options";
import { FilterWrapper } from "../../components/filter-wrapper";

export default async function StatisticalVariablesFilter() {
  const client = await createPostgRESTSSRClient();
  const statDefinitions = await client.from("stat_definition_active").select();

  return (
    <>
      {await Promise.all(statDefinitions.data?.map(async (statDefinition) => (
        <FilterWrapper 
          key={"stat_var"+statDefinition.code!}
          columnCode="statistic"
          statCode={statDefinition.code}
        >
          <StatisticalVariablesOptions
            statDefinition={statDefinition}
          />
        </FilterWrapper>
      )) ?? [])}
    </>
  );
}

