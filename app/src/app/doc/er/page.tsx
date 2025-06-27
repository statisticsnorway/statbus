import ErDiagramClientComponent from "./er-diagram-client";
import { DetailsPageHeader } from "@/components/statistical-unit-details/details-page-header";

export default function ErDiagramPage() {
  return (
    <div className="p-4">
      <DetailsPageHeader
        title="Entity-Relationship Diagram"
        subtitle="Auto-generated from the database schema."
      />
      <ErDiagramClientComponent />
    </div>
  );
}
