import { Metadata } from "next";
import {
  DetailsPageLayout,
  DetailsPageLayoutProps,
} from "@/components/statistical-unit-details/details-page-layout";

export const metadata: Metadata = {
  title: "Details",
};

export default function SettingsLayout({
  children,
  header,
  nav,
  primaryUnitInfo,
}: DetailsPageLayoutProps) {
  return (
    // The enterprise's primaryUnitInfo is its "Derived from" line, read
    // before the menu (64ae2w, owner 2026-11-21).
    <DetailsPageLayout
      header={header}
      nav={
        <>
          {primaryUnitInfo}
          {nav}
        </>
      }
      primaryUnitInfo={null}
    >
      {children}
    </DetailsPageLayout>
  );
}
