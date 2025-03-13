import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import StatisticalVariablesForm from "./statistical-variables-form";
import { getStatisticalUnitStats } from "@/components/statistical-unit-details/requests";
import { notFound } from "next/navigation";

export default async function LegalUnitStatisticalVariablesPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { stats, error } = await getStatisticalUnitStats(
    parseInt(id),
    "legal_unit"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!stats) {
    return;
  }

  const legalUnitStats = stats.find(
    (s) => s.unit_type === "legal_unit" && s.unit_id === parseInt(id)
  );

  if (!legalUnitStats) {
    notFound();
  }

  return (
    <DetailsPage
      title="Statistical variables"
      subtitle="Statistical variables such as employees, turnover"
    >
      <StatisticalVariablesForm legalUnitStats={legalUnitStats} />
    </DetailsPage>
  );
}
