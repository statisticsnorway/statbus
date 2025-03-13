import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import StatisticalVariablesForm from "./statistical-variables-form";
import { getStatisticalUnitStats } from "@/components/statistical-unit-details/requests";
import { notFound } from "next/navigation";

export default async function EstablishmentStatisticalVariablesPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { stats, error } = await getStatisticalUnitStats(
    parseInt(id),
    "establishment"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!stats) {
    return;
  }

  const establishmentStats = stats.find(
    (stat) =>
      stat.unit_type === "establishment" && stat.unit_id === parseInt(id)
  );

  if (!establishmentStats) {
    notFound();
  }

  return (
    <DetailsPage
      title="Statistical variables"
      subtitle="Statistical variables such as employees, turnover"
    >
      <StatisticalVariablesForm establishmentStats={establishmentStats} />
    </DetailsPage>
  );
}
