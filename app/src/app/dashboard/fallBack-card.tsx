import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Loader } from "lucide-react";

export const FallBackCard = ({ title }: { readonly title: string }) => {
  return (
    <DashboardCard
      title={title}
      icon={<Loader className="h-4 animate-spin" />}
      text="&nbsp;"
    />
  );
};
