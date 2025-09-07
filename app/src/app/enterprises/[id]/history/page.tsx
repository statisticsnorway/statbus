import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitHistory } from "@/components/statistical-unit-details/requests";
import React from "react";
import { Metadata } from "next";
import { HistoryChart } from "./history-chart";

export const metadata: Metadata = {
  title: "Enterprise | History",
};

export default async function EnterpriseHistoryPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  const { data: history, error } = await getStatisticalUnitHistory(
    parseInt(id, 10),
    "enterprise"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!history) {
    notFound();
  }

  return (
    <DetailsPage title="History" subtitle="Statistical history for the unit">
      <HistoryChart history={history} />
    </DetailsPage>
  );
}
