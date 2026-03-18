"use client";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { Tables } from "@/lib/database.types";
import { useAdminForm } from "../use-admin-form";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { ExternalIdentTypeForm } from "./external-idents-form";
import { useExternalIdentTypes } from "./use-external-idents";
import { useBaseData } from "@/atoms/base-data";
import AdminPageLayout from "../page-layout";
import BooleanBadge from "../boolean-badge";

const columns: ColumnDefinition<Tables<"external_ident_type">>[] = [
  { key: "name", header: "Name" },
  { key: "code", header: "Code" },
  {
    key: "description",
    header: "Description",
    className: "whitespace-normal max-w-52",
  },
  { key: "shape", header: "Type" },
  {
    key: "labels",
    header: "Labels",
    render: (record) => record.labels ?? "",
  },
  { key: "priority", header: "Priority" },
  {
    key: "enabled",
    header: "Enabled",
    render: (record) => <BooleanBadge value={record.enabled} />,
  },
];

export default function ExternalIdentTypesPage() {
  const { externalIdentTypes, refreshExternalIdentTypes, isLoading } =
    useExternalIdentTypes();
  const { refreshBaseData } = useBaseData();
  const {
    isFormOpen,
    handleCreate,
    handleEdit,
    selectedRecord,
    formKey,
    handleOpenChange,
    handleSuccess,
  } = useAdminForm<Tables<"external_ident_type">>({
    onSuccess: () => {
      refreshExternalIdentTypes();
      refreshBaseData();
    },
  });

  return (
    <AdminPageLayout
      title="External Identifier Types"
      subtitle="View, create and manage external identifier types"
    >
      <div className="flex items-center justify-end mb-2">
        <Button onClick={handleCreate}>
          <Plus className="w-4 h-4" />
          Add new external ident
        </Button>
        <ExternalIdentTypeForm
          key={formKey}
          isOpen={isFormOpen}
          onOpenChange={handleOpenChange}
          externalIdentType={selectedRecord}
          onSuccess={handleSuccess}
        />
      </div>
      <div className="rounded-md border overflow-hidden">
        <AdminTable
          data={externalIdentTypes}
          columns={columns}
          onEdit={handleEdit}
          isLoading={isLoading}
        />
      </div>
    </AdminPageLayout>
  );
}
