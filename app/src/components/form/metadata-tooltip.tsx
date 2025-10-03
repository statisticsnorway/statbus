import { InfoIcon } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "../ui/tooltip";
import { useBaseData } from "@/atoms/base-data";
import { Tables } from "@/lib/database.types";
import { useDetailsPageData } from "@/atoms/edits";
import { format } from "date-fns";
import { Fragment, useMemo } from "react";

type MetadataTooltipProps = {
  metadata: Metadata;
};

const formatDate = (date?: string | null) =>
  date ? format(new Date(date), "yyyy-MM-dd") : null;
const formatDateTime = (dateTime?: string | null) =>
  dateTime ? format(new Date(dateTime), "yyyy-MM-dd HH:mm:ss") : null;

export const MetadataTooltip = ({ metadata }: MetadataTooltipProps) => {
  const {
    edit_at,
    edit_by_user_id,
    edit_comment,
    data_source_id,
    valid_from,
    valid_to,
  } = metadata;
  const { statbusUsers } = useBaseData();
  const { dataSources } = useDetailsPageData();
  const dataSourcesMap = useMemo(
    () => new Map(dataSources.map((ds) => [ds.id, ds.name])),
    [dataSources]
  );
  const dataSourceName = data_source_id
    ? dataSourcesMap.get(data_source_id)
    : null;

  const userMap = useMemo(() => {
    return new Map(
      statbusUsers.map((user: Tables<"user">) => [
        user.id,
        user.email?.split("@")[0].replace(/\./, " "),
      ])
    );
  }, [statbusUsers]);
  const editByUser = edit_by_user_id ? userMap.get(edit_by_user_id) : null;

  const metadataItems: Array<{ label: string; value: string | null }> = [
    { label: "Valid from", value: formatDate(valid_from) },
    {
      label: "Valid to",
      value:
        valid_to === "infinity"
          ? "Present"
          : valid_to
            ? formatDate(valid_to)
            : "N/A",
    },
    { label: "Data source", value: dataSourceName ?? "N/A" },
    { label: "Last edited by", value: editByUser ?? "N/A" },
    { label: "Last edited at", value: formatDateTime(edit_at) },
    { label: "Edit comment", value: edit_comment },
  ];

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <InfoIcon className="h-4 w-4 ml-2 text-gray-400" />
        </TooltipTrigger>
        <TooltipContent>
          <dl className="grid grid-cols-[auto_1fr] gap-x-2 text-sm">
            {metadataItems.map(({ label, value }) => (
              <Fragment key={label}>
                <dt className="text-right font-semibold">{label}:</dt>
                <dd className="truncate">{value}</dd>
              </Fragment>
            ))}
          </dl>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
};
