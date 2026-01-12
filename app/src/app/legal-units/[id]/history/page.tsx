import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitHistoryHighcharts } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";
import { HistoryChart } from "@/components/statistical-unit-details/unit-history-chart";

export const metadata: Metadata = {
  title: "Legal Unit | History",
};

export default async function LegalUnitHistoryPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;


  const { data: historyHighcharts, error } =
    await getStatisticalUnitHistoryHighcharts(parseInt(id, 10), "legal_unit");

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!historyHighcharts) {
    notFound();
  }

  return (
    <DetailsPage title="History" subtitle="Statistical history for the unit">
      <HistoryChart historyHighcharts={historyHighcharts} />
    </DetailsPage>
  );
}
