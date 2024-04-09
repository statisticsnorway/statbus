import { createClient } from "@/lib/supabase/server";
import StatisticalVariablesOptions from "@/app/search/filtersV2/statistical-variables/statistical-variables-options";

export default async function StatisticalVariablesFilter({
  urlSearchParams,
}: {
  readonly urlSearchParams: URLSearchParams;
}) {
  const resolve = createURLParamsResolver(new URLSearchParams(urlSearchParams));
  const client = createClient();
  const statisticalVariables = await client
    .from("stat_definition")
    .select()
    .order("priority", { ascending: true });

  return (
    <>
      {statisticalVariables.data?.map(({ code, name }) => {
        const [value, operator] = resolve(code);
        return (
          <StatisticalVariablesOptions
            key={code}
            label={name}
            code={code}
            selected={value && operator ? { operator, value } : undefined}
          />
        );
      })}
    </>
  );
}

/**
 * Returns a function that resolves value and operator from a URLSearchParams instance.
 * A param typically looks like this: ?name=in.legal_unit,establishment,enterprise which
 * will resolve to ["legal_unit,establishment,enterprise", "in"]
 * If the parameter is not present, it will return null values for both value and operator
 *
 * Example:
 * const params = new URLSearchParams("?name=in.legal_unit,establishment,enterprise");
 * const resolve = createURLParamsResolver(params);
 * const [value, operator] = resolve("name");
 *
 * @param params URLSearchParams
 */
const createURLParamsResolver =
  (params: URLSearchParams) =>
  (name: string): [string | null, string | null] => {
    const param = params.get(name);
    if (!param) return [null, null];
    const dotIndex = param.indexOf(".");
    const operator = param.substring(0, dotIndex);
    const value = param.substring(dotIndex + 1);
    return [value, operator];
  };
