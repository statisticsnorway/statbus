"use client"
import { Tables } from "@/lib/database.types";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { useAdminForm } from "../use-admin-form";
import AdminPageLayout from "../page-layout";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { useStatusCodes } from "./use-statuses";
import { StatusForm } from "./status-form";
import BooleanBadge from "../boolean-badge";


const columns: ColumnDefinition<Tables<"status">>[] = [
  { key: "name", header: "Name" },
  { key: "code", header: "Code" },
  {
    key: "custom",
    header: "Custom",
    render: (record) => <BooleanBadge value={record.custom} />,
  },
  {
    key: "assigned_by_default",
    header: "Assigned by default",
    render: (record) => <BooleanBadge value={record.assigned_by_default} />,
  },
  {
    key: "used_for_counting",
    header: "Used for counting",
    render: (record) => <BooleanBadge value={record.used_for_counting} />,
  },
  { key: "priority", header: "Priority" },
  {
    key: "enabled",
    header: "Enabled",
    render: (record) => <BooleanBadge value={record.enabled} />,
  },
];

export default function StatusCodesPage() {
  const { statusCodes, refreshStatusCodes, isLoading } = useStatusCodes();
  const {
    isFormOpen,
    handleCreate,
    handleEdit,
    selectedRecord,
    formKey,
    handleOpenChange,
    handleSuccess,
  } = useAdminForm<Tables<"status">>({
    onSuccess: () => {
      refreshStatusCodes();
    },
  });
  return (
    <AdminPageLayout
      title="Statuses"
      subtitle="View, create and manage statuses"
    >
      <div className="flex items-center justify-end mb-2">
        <Button onClick={handleCreate}>
          <Plus className="w-4 h-4" />
          Add new status
        </Button>
        <StatusForm
          key={formKey}
          isOpen={isFormOpen}
          onOpenChange={handleOpenChange}
          statusCode={selectedRecord}
          onSuccess={handleSuccess}
        />
      </div>
      <div className="rounded-md border overflow-hidden">
        <AdminTable
          data={statusCodes}
          columns={columns}
          onEdit={handleEdit}
          isLoading={isLoading}
        />
      </div>
    </AdminPageLayout>
  );
}
