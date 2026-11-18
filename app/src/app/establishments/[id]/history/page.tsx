import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import {
  getStatisticalUnitHistoryHighcharts,
} from "@/components/statistical-unit-details/requests";
import { getServerRestClient } from "@/context/RestClientStore";
import { fetchUnitHistoryPage } from "@/components/statistical-unit-details/unit-history-page";
import { Metadata } from "next";
import { HistoryChart } from "@/components/statistical-unit-details/unit-history-chart";
import UnitHistoryTable from "@/components/statistical-unit-details/unit-history-table";

export const metadata: Metadata = {
  title: "Establishment | History",
};

export default async function EstablishmentHistoryPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  const [{ data: historyHighcharts, error: highchartsError }, firstPage] =
    await Promise.all([
      getStatisticalUnitHistoryHighcharts(parseInt(id, 10), "establishment"),
      getServerRestClient().then((client) =>
        fetchUnitHistoryPage(client, parseInt(id, 10), "establishment", 0)
      ),
    ]);

  if (highchartsError || firstPage.error) {
    throw new Error(highchartsError?.message || firstPage.error?.message);
  }

  // A unit always has history rows; the chart needs statistical variables, which a unit may lack.
  if (!firstPage.versions.length) {
    notFound();
  }

  return (
    <DetailsPage title="History" subtitle="Statistical history for the unit">
      {historyHighcharts.series.length > 0 && (
        <HistoryChart historyHighcharts={historyHighcharts} />
      )}
      <UnitHistoryTable
        firstPage={firstPage}
        unitId={parseInt(id, 10)}
        unitType="establishment"
      />
    </DetailsPage>
  );
}
