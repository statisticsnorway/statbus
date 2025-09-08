"use client";
import LegalFormOptions from "@/app/search/filters/legal-form/legal-form-options";
import { useSearchPageData } from "@/atoms/search";

export default function LegalFormFilter() {
  const { allLegalForms } = useSearchPageData();

  return (
    <LegalFormOptions
      options={
        allLegalForms?.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })) ?? []
      }
    />
  );
}
