import { Metadata } from "next";
import Dashboard from "@/app/dashboard/page";

export const metadata: Metadata = {
  title: "StatBus | Home",
};

export default async function Home() {
  return <Dashboard />;
}
