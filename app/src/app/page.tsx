import { Metadata } from "next";
import Dashboard from "@/app/dashboard/page";
import { deploymentSlotName } from "@/lib/deployment-variables";

export const metadata: Metadata = {
  title: `${deploymentSlotName} Statbus | Home`,
};

export default async function Home() {
  return <Dashboard />;
}
