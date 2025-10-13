"use client";
import LastEditByUserOptions from "@/app/search/filters/last-edit-by-user/last-edit-by-user-options";
import { useBaseData } from "@/atoms/base-data";
import { useMemo } from "react";

export default function LastEditByUserFilter() {
  const { statbusUsers } = useBaseData(); 

  return (
    <LastEditByUserOptions
      options={
        statbusUsers?.map(({ id, display_name }) => ({
          label: display_name!,
          value: id?.toString()!,
          humanReadableValue: display_name!,
        })) ?? []
      }
    />
  );
}
