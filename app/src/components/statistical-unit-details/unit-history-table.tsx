"use client";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tables } from "@/lib/database.types";
import { useBaseData } from "@/atoms/base-data";
import { cn } from "@/lib/utils";
import { format } from "date-fns";
import { useMemo } from "react";

type CodeName = { code: string | null; name: string } | null;

export interface UnitHistory extends Tables<"statistical_unit"> {
  valid_from: string | null;
  valid_to: string | null;
  physical_region: CodeName;
  primary_activity_category: CodeName;
  secondary_activity_category: CodeName;
  sector: CodeName;
  legal_form: CodeName;
  status: CodeName;
  stats: Record<string, { type: string; value: number | string | null }> | null;
}

type Column = {
  header: string;
  cellClassName?: string;
  render: (unit: UnitHistory) => React.ReactNode;
};

export default function UnitHistoryTable({
  unitHistory,
  unitId,
  unitType,
}: {
  readonly unitHistory: UnitHistory[] | null;
  readonly unitId: number;
  readonly unitType: "legal_unit" | "establishment" | "enterprise";
}) {
  const { statDefinitions, statbusUsers } = useBaseData();
  const usersById = useMemo(
    () => new Map(statbusUsers.map((u) => [u.id, u.display_name])),
    [statbusUsers]
  );

  const columns = useMemo<Column[]>(
    () => [
      { header: "Valid from", render: (u) => u.valid_from },
      { header: "Name", render: (u) => u.name },
      {
        header: "Primary Activity",
        render: (u) => <CodeNameCell item={u.primary_activity_category} />,
      },
      {
        header: "Region",
        render: (u) => <CodeNameCell item={u.physical_region} />,
      },
      { header: "Status", render: (u) => u.status?.name },
      ...statDefinitions.map(
        (sd): Column => ({
          header: sd.name ?? "",
          render: (u) => u.stats?.[sd.code!]?.value,
        })
      ),
      { header: "Unit size", render: (u) => u.unit_size_code },
      {
        header: "Secondary Activity",
        render: (u) => <CodeNameCell item={u.secondary_activity_category} />,
      },
      { header: "Sector", render: (u) => <CodeNameCell item={u.sector} /> },
      {
        header: "Legal Form",
        render: (u) => <CodeNameCell item={u.legal_form} />,
      },
      {
        header: "Physical Address",
        cellClassName: "grid w-64 gap-1",
        render: (u) => (
          <>
            <AddressCell
              parts={[
                u.physical_address_part1,
                u.physical_address_part2,
                u.physical_address_part3,
              ]}
            />
            <AddressCell
              parts={[
                u.physical_postcode,
                u.physical_postplace,
                u.physical_country_iso_2,
              ]}
            />
          </>
        ),
      },
      {
        header: "Coordinates",
        render: (u) => (
          <CoordinatesCell
            lat={u.physical_latitude}
            lng={u.physical_longitude}
            alt={u.physical_altitude}
          />
        ),
      },
      {
        header: "Postal Address",
        cellClassName: "grid w-64 gap-1",
        render: (u) => (
          <>
            <AddressCell
              parts={[
                u.postal_address_part1,
                u.postal_address_part2,
                u.postal_address_part3,
              ]}
            />
            <AddressCell
              parts={[
                u.postal_postcode,
                u.postal_postplace,
                u.postal_country_iso_2,
              ]}
            />
          </>
        ),
      },
      { header: "Email address", render: (u) => u.email_address },
      { header: "Web address", render: (u) => u.web_address },
      { header: "Phone number", render: (u) => u.phone_number },
      { header: "Landline", render: (u) => u.landline },
      { header: "Mobile number", render: (u) => u.mobile_number },
      { header: "Fax number", render: (u) => u.fax_number },
      {
        header: "Data source",
        render: (u) => u.data_source_codes?.join(", "),
      },
      {
        header: "Last edit",
        render: (u) => (
          <div className="flex flex-col space-y-0.5 leading-tight whitespace-nowrap">
            <small className="text-gray-700">
              {u.last_edit_at
                ? format(new Date(u.last_edit_at), "yyyy-MM-dd HH:mm")
                : ""}
            </small>
            <small className="text-gray-700">
              By {usersById.get(u.last_edit_by_user_id)}
            </small>
          </div>
        ),
      },
      { header: "Edit comment", render: (u) => u.last_edit_comment },
    ],
    [statDefinitions, usersById]
  );

  if (!unitHistory) return null;

  return (
    <div className="space-y-2">
      <Table>
        <TableHeader className="bg-gray-50 border-t">
          <TableRow>
            {columns.map((col, i) => (
              <TableHead key={`${col.header}-${i}`}>{col.header}</TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {unitHistory.map((unit) => (
            <TableRow key={unit.valid_from}>
              {columns.map((col, i) => (
                <TableCell
                  key={`${col.header}-${i}`}
                  className={col.cellClassName}
                >
                  {col.render(unit)}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function CodeNameCell({
  item,
}: {
  item: { code?: string | null; name?: string | null } | null;
}) {
  if (!item) return null;
  return (
    <div className="flex flex-col space-y-0.5 leading-tight">
      <span>{item.code}</span>
      <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-36">
        {item.name}
      </small>
    </div>
  );
}

function AddressCell({
  className,
  parts,
}: {
  className?: string;
  parts: (string | null | undefined)[];
}) {
  return (
    <small className={cn(className, "text-wrap line-clamp-2")}>
      {parts.filter(Boolean).join(", ")}
    </small>
  );
}

function CoordinatesCell({
  lat,
  lng,
  alt,
}: {
  lat: number | null;
  lng: number | null;
  alt: number | null;
}) {
  return (
    <small className="grid grid-cols-3 space-y-0.5 leading-tight">
      <span className="text-gray-400">lat:</span>
      {lat != null && <span className="col-span-2">{lat}</span>}
      <span className="text-gray-400">lng:</span>
      {lng != null && <span className="col-span-2">{lng}</span>}
      <span className="text-gray-400">alt:</span>{" "}
      {alt != null && <span className="col-span-2">{alt}</span>}
    </small>
  );
}
