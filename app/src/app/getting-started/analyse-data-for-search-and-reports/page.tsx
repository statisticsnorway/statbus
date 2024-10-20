import Link from "next/link";
import { StatisticalUnitsRefresher } from "./statistical-units-refresher";

export default function RefreshStatisticalUnitsPage() {
  return (
    <div className="space-y-8">
      <h1 className="text-center text-2xl">Analyse data for Search and Reports</h1>
      <p className="leading-loose">
        Analysis for data for Search and Reports may take some time, depending on the amount
        of data being processed.
      </p>
      <StatisticalUnitsRefresher>
        <div className="text-center">
          <Link className="underline" href="/getting-started/summary">
            Go to Summary
          </Link>
        </div>
      </StatisticalUnitsRefresher>
    </div>
  );
}
