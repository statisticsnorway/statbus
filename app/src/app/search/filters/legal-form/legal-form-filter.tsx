import { getServerRestClient } from "@/context/RestClientStore";
import LegalFormOptions from "@/app/search/filters/legal-form/legal-form-options";

export default async function LegalFormFilter() {
  const client = await getServerRestClient();
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
    />
  );
}
