import { Metadata } from "next";
import {
  DetailsPageLayout,
  DetailsPageLayoutProps,
} from "@/components/statistical-unit-details/details-page-layout";

export const metadata: Metadata = {
  title: "Legal Unit",
};

export default function Layout({ children, header, nav }: DetailsPageLayoutProps) {
  return (
    <DetailsPageLayout header={header} nav={nav}>
      {children}
    </DetailsPageLayout>
  );
}
