"use client";
import { FormField } from "@/components/form/form-field";
import { useCustomConfigContext } from "@/app/use-custom-config-context";

export default function GeneralInfoForm({
  values,
}: {
  readonly values: LegalUnit;
}) {
  const { externalIdentTypes } = useCustomConfigContext();

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
