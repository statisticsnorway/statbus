import {Metadata} from "next"
import {DetailsPageLayout, DetailsPageLayoutProps} from "@/components/statistical-unit-details/details-page-layout";

export const metadata: Metadata = {
  title: "Details"
}

export default function SettingsLayout({children, header, topology, nav}: DetailsPageLayoutProps) {
  return (
    <DetailsPageLayout header={header} nav={nav} topology={topology}>{children}</DetailsPageLayout>
  )
}



