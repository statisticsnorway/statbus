import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import {
  getStatisticalUnitHistory,
  getStatisticalUnitHistoryHighcharts,
} from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";
import { HistoryChart } from "@/components/statistical-unit-details/unit-history-chart";
import UnitHistoryTable from "@/components/statistical-unit-details/unit-history-table";

export const metadata: Metadata = {
  title: "Legal Unit | History",
};

export default async function LegalUnitHistoryPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  const [
    { data: historyHighcharts, error: highchartsError },
    { data: unitHistory, error: unitHistoryError },
  ] = await Promise.all([
    getStatisticalUnitHistoryHighcharts(parseInt(id, 10), "legal_unit"),
    getStatisticalUnitHistory(parseInt(id, 10), "legal_unit"),
  ]);

  if (highchartsError || unitHistoryError) {
    throw new Error(highchartsError?.message || unitHistoryError?.message);
  }

  if (historyHighcharts.series.length === 0 || unitHistory?.length === 0) {
    notFound();
  }

  return (
    <DetailsPage title="History" subtitle="Statistical history for the unit">
      <HistoryChart historyHighcharts={historyHighcharts} />
      <UnitHistoryTable unitHistory={unitHistory} />
    </DetailsPage>
  );
}
