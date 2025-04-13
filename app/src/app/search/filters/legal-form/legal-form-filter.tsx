import { getServerClient } from "@/context/ClientStore";
import LegalFormOptions from "@/app/search/filters/legal-form/legal-form-options";

export default async function LegalFormFilter() {
  const client = await getServerClient();
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
