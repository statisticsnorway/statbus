"use client";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { Tables } from "@/lib/database.types";
import { useAdminForm } from "../use-admin-form";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { useBaseData } from "@/atoms/base-data";
import { useStatDefinitions } from "./use-statistical-variables";
import { StatDefinitionForm } from "./statistical-variables-form";
import AdminPageLayout from "../page-layout";
import BooleanBadge from "../boolean-badge";

const columns: ColumnDefinition<Tables<"stat_definition">>[] = [
  { key: "name", header: "Name" },
  { key: "code", header: "Code" },
  {
    key: "description",
    header: "Description",
    className: "whitespace-normal max-w-52",
  },
  { key: "type", header: "Type" },
  { key: "frequency", header: "Frequency" },
  { key: "priority", header: "Priority" },
  {
    key: "enabled",
    header: "Enabled",
    render: (record) => <BooleanBadge value={record.enabled} />,
  },
];

export default function StatisticalVariablesPage() {
  const { statDefinitions, refreshStatDefinitions, isLoading } = useStatDefinitions();
  const { refreshBaseData } = useBaseData();
  const {
    isFormOpen,
    handleCreate,
    handleEdit,
    selectedRecord,
    formKey,
    handleOpenChange,
    handleSuccess,
  } = useAdminForm<Tables<"stat_definition">>({
    onSuccess: () => {
      refreshStatDefinitions();
      refreshBaseData();
    },
  });

  return (
    <AdminPageLayout
      title="Statistical Variables"
      subtitle="View, create and manage statistical variables"
    >
      <div className="flex items-center justify-end mb-2">
        <Button onClick={handleCreate}>
          <Plus className="w-4 h-4" />
          Add new statistical variable
        </Button>
        <StatDefinitionForm
          key={formKey}
          isOpen={isFormOpen}
          onOpenChange={handleOpenChange}
          statDefinition={selectedRecord}
          onSuccess={handleSuccess}
        />
      </div>
      <div className="rounded-md border overflow-hidden">
        <AdminTable
          data={statDefinitions}
          columns={columns}
          onEdit={handleEdit}
          isLoading={isLoading}
        />
      </div>
    </AdminPageLayout>
  );
}
