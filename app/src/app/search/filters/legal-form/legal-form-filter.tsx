import { createClient } from "@/utils/supabase/server";
import LegalFormOptions from "@/app/search/filters/legal-form/legal-form-options";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default async function LegalFormFilter({
  urlSearchParam: param,
}: IProps) {
  const client = await createClient();
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
      selected={param ? param.split(",") : []}
    />
  );
}
