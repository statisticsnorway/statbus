import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import StatisticalVariablesForm from "./statistical-variables-form";

export default async function EnterpriseStatisticalVariablesPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  return (
    <DetailsPage
      title="Statistical variables"
      subtitle="Statistical variables such as employees, turnover"
    >
      <StatisticalVariablesForm id={id} />
    </DetailsPage>
  );
}
