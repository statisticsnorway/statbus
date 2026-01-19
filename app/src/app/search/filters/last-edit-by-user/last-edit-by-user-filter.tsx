"use client";
import LastEditByUserOptions from "@/app/search/filters/last-edit-by-user/last-edit-by-user-options";
import { getUserPermissions } from "@/atoms/auth";
import { useBaseData } from "@/atoms/base-data";

export default function LastEditByUserFilter() {
  const { statbusUsers } = useBaseData();

  const usersWithEditAccess = statbusUsers?.filter((user) => {
    const permisions = getUserPermissions(user.statbus_role);
    return permisions.canEdit;
  });

  return (
    <LastEditByUserOptions
      options={
        usersWithEditAccess?.map(({ id, display_name }) => ({
          label: display_name!,
          value: id?.toString()!,
          humanReadableValue: display_name!,
        })) ?? []
      }
    />
  );
}

