import { ReactNode } from "react";
import { EditStateResetter } from "./edit-state-resetter";
import { UnitNotesForPage } from "@/components/unit-notes/unit-notes-for-page";

export interface DetailsPageLayoutProps {
  readonly children: ReactNode;
  readonly header: ReactNode;
  readonly nav: ReactNode;
  readonly primaryUnitInfo?: ReactNode;
}

export const DetailsPageLayout = ({
  children,
  header,
  nav,
  primaryUnitInfo,
}: DetailsPageLayoutProps) => (
  // Readable max width for forms, lifted to the full screen when a section
  // marks itself wide (DetailsPage `wide`: the history table).
  <main className="mx-auto w-full min-w-0 max-w-6xl has-[[data-wide-content]]:max-w-none space-y-6 px-2 py-2 lg:py-4">
    <EditStateResetter />
    {header}
    <div className="flex flex-col lg:flex-row space-x-4 space-y-8  lg:space-y-0">
      <aside className="lg:w-3/12">
        {nav}
        {primaryUnitInfo}
        <UnitNotesForPage />
      </aside>
      <div className="lg:w-9/12">
        <div className="flex-1">{children}</div>
      </div>
    </div>
  </main>
);
