"use client";
import { useBaseData } from "@/app/BaseDataClient";
import { FormField } from "@/components/form/form-field";

export default function GeneralInfoForm({
  values,
}: {
  readonly values: LegalUnit | Establishment;
}) {
  const { externalIdentTypes } = useBaseData();

  return (
    <form className="space-y-8">
      <FormField
        readonly
        label="Name"
        name="name"
        value={values.name}
        response={null}
      />
      {Object.keys(values.external_idents).map((key) => {
        const externalIdentType = externalIdentTypes.find(
          (type) => key === type.code
        );
        return (
          <FormField
            readonly
            key={key}
            label={externalIdentType?.name ?? key}
            name={`external_idents.${key}`}
            value={values.external_idents[key]}
            response={null}
          />
        );
      })}
    </form>
  );
}
