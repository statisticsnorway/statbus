"use client";

import { ReactNode, useEffect, useState } from "react";
import { PostgrestError } from "@supabase/postgrest-js";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { format } from "date-fns";
import { useBaseData } from "@/atoms/base-data";
import { Database } from "lucide-react";
import { Tables } from "@/lib/database.types";
import { DashboardSection } from "./dashboard-section";

export const DashboardClientContent = ({
  children,
}: {
  children: ReactNode;
}) => {
  const { statbusUsers } = useBaseData();
  const [editInfo, setEditInfo] = useState<{
    data: {
      last_edit_at: string | null;
      last_edit_by_user_id: number | null;
    } | null;
    error: PostgrestError | null;
  }>({ data: null, error: null });

  useEffect(() => {
    const fetchData = async () => {
      const client = await getBrowserRestClient();
      const { data, error } = await client
        .from("statistical_unit")
        .select("last_edit_at, last_edit_by_user_id")
        .order("last_edit_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      setEditInfo({ data, error });
    };
    fetchData();
  }, []);

  const { data } = editInfo;

  const formattedLastEditAt = data?.last_edit_at
    ? format(new Date(data.last_edit_at), "yyyy-MM-dd HH:mm:ss")
    : null;

  const lastEditBy = data?.last_edit_by_user_id
    ? statbusUsers
        .find((u: Tables<"user">) => u.id === editInfo.data?.last_edit_by_user_id)
        ?.email?.split("@")[0]
        .replace(/\./, " ")
    : null;

  return (
    <DashboardSection
      title="Data Metrics"
      icon={<Database className="w-4 h-4 stroke-current" />}
      lastEditAt={formattedLastEditAt}
      lastEditBy={lastEditBy}
    >
      {children}
    </DashboardSection>
  );
};
