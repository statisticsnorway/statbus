import { createClient } from "@/lib/supabase/server";
import LegalFormOptions from "@/app/search/filtersV2/legal-form/legal-form-options";

export default async function LegalFormFilter() {
  const client = createClient();
  const legalForms = await client
    .from("legal_form_used")
    .select()
    .not("code", "is", null);

  await new Promise((resolve) => setTimeout(resolve, 1500));

  // TODO: remove demo delay
  // TODO: pass url search params to Child Component

  return (
    <LegalFormOptions
      options={
        legalForms.data?.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })) ?? []
      }
      selected={[]}
    />
  );
}
