import Link from "next/link";
import { StatisticalUnitsRefresher } from "./statistical-units-refresher";
import { NavbarStatusVisualizer } from "./navbar-status-visualizer";

export default function RefreshStatisticalUnitsPage() {
  return (
    <div className="space-y-8">
      <h1 className="text-center text-2xl">
        Analyse data for Search and Reports
      </h1>
      <p className="leading-loose mb-6">
        Analysis for data for Search and Reports may take some time, depending
        on the amount of data being processed.
      </p>
      
      <StatisticalUnitsRefresher>
        <div className="text-center mt-4">
          <Link className="underline text-blue-600 hover:text-blue-800" href="/import/summary">
            Go to Summary
          </Link>
        </div>
      </StatisticalUnitsRefresher>
      
      <div className="bg-gray-50 p-6 rounded-lg">
        <h2 className="text-lg font-medium mb-4">Navigation Status Indicators</h2>
        
        <NavbarStatusVisualizer />
        
        <p className="mt-4 text-sm text-gray-600">
          The navigation bar above shows how processing status is indicated in the main navigation.
          Yellow borders indicate active processing, while white borders show the current page.
          When no processing is happening, only the current page will have a border.
        </p>
      </div>
    </div>
  );
}
