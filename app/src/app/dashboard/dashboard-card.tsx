import { ReactNode } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export const DashboardCard = ({
  title,
  icon,
  text,
  failed,
  className,
}: {
  readonly title: string;
  readonly icon: ReactNode;
  readonly text: string;
  readonly failed?: boolean;
  readonly className?: string;
}) => {
  return (
    <Card className={cn("overflow-hidden", className)}>
      <CardHeader
        className={cn(
          "flex flex-row items-center justify-between space-y-0 bg-gray-100 px-3 py-2",
          failed ? "border-orange-400 bg-orange-100" : ""
        )}
      >
        <CardTitle className="text-xs font-medium">{title}</CardTitle>
        {icon}
      </CardHeader>
      <CardContent className="space-y-3 px-3 py-3">
        <div className="text-right text-xl font-semibold">{text}</div>
      </CardContent>
    </Card>
  );
};
