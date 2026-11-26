import { ReactNode } from "react";

export const DashboardSection = ({
  title,
  icon,
  lastEditAt,
  lastEditBy,
  settings,
  children,
}: {
  title: string;
  icon: ReactNode;
  lastEditAt?: string | null;
  lastEditBy?: string | null;
  /** A control beside the section's icon that opens where the section is configured. */
  settings?: ReactNode;
  children?: ReactNode;
}) => {
  return (
    <div>
      <div className="flex justify-between items-center border border-b-0 py-2 px-4 rounded-t bg-gray-100">
        <h2 className="text-xs uppercase font-semibold">{title}</h2>
        <div className="flex items-center gap-2">
          {lastEditAt && lastEditBy && (
            <p className="text-xs text-zinc-500 mr-2">
              Last update: {lastEditAt} by {lastEditBy}
            </p>
          )}
          {settings}
          {icon}
        </div>
      </div>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4 p-2 lg:p-4 border border-t-0 rounded-b">
        {children}
      </div>
    </div>
  );
};
