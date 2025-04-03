import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitStats } from "@/components/statistical-unit-details/requests";
import { notFound } from "next/navigation";
import StatisticalVariablesForm from "./statistical-variables-form";

export default async function EnterpriseStatisticalVariablesPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

  const { stats, error } = await getStatisticalUnitStats(
    parseInt(id),
    "enterprise"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!stats) {
    return;
  }

  const enterpriseStats = stats.find(
    (stat) => stat.unit_type === "enterprise" && stat.unit_id === parseInt(id)
  );

  if (!enterpriseStats) {
    notFound();
  }

  return (
    <DetailsPage
      title="Statistical variables"
      subtitle="Statistical variables such as employees, turnover"
    >
      <StatisticalVariablesForm enterpriseStats={enterpriseStats} />
    </DetailsPage>
  );
}
