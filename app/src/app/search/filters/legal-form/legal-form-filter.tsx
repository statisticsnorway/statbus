import { createSupabaseSSRClient } from "@/utils/supabase/server";
import LegalFormOptions from "@/app/search/filters/legal-form/legal-form-options";
import { LEGAL_FORM } from "../url-search-params";

import { IURLSearchParamsDict, toURLSearchParams } from "@/lib/url-search-params-dict";

export default async function LegalFormFilter({ initialUrlSearchParamsDict: initialUrlSearchParams }: IURLSearchParamsDict) {
  const urlSearchParams = toURLSearchParams(initialUrlSearchParams);

  const legalForm = urlSearchParams.get(LEGAL_FORM);
  const client = await createSupabaseSSRClient();
  const legalForms = await client
    .from("legal_form_used")
    .select()
    .not("code", "is", null);

  return (
    <LegalFormOptions
      options={
        legalForms.data?.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })) ?? []
      }
      selected={legalForm ? legalForm.split(",") : []}
    />
  );
}
