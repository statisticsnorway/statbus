"use client"
import { Tables } from "@/lib/database.types";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { useUnitSizes } from "./use-unit-sizes";
import { useAdminForm } from "../use-admin-form";
import AdminPageLayout from "../page-layout";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { UnitSizeForm } from "./unit-size-form";
import BooleanBadge from "../boolean-badge";


const columns: ColumnDefinition<Tables<"unit_size">>[] = [
  { key: "name", header: "Name" },
  { key: "code", header: "Code" },
  {
    key: "custom",
    header: "Custom",
    render: (record) => <BooleanBadge value={record.custom} />,
  },
  {
    key: "enabled",
    header: "Enabled",
    render: (record) => <BooleanBadge value={record.enabled} />,
  },
];

export default function UnitSizesPage() {
    const {unitSizes, refreshUnitSizes, isLoading} = useUnitSizes()
    const {
        isFormOpen, handleCreate, handleEdit, selectedRecord, formKey, handleOpenChange, handleSuccess
    } = useAdminForm<Tables<"unit_size">>({
        onSuccess: () => {
            refreshUnitSizes();
        }
    })
    return (
      <AdminPageLayout
        title="Unit Sizes"
        subtitle="View, create and manage unit sizes"
      >
        <div className="flex items-center justify-end mb-2">
          <Button onClick={handleCreate}>
            <Plus className="w-4 h-4" />
            Add new unit size
          </Button>
          <UnitSizeForm
            key={formKey}
            isOpen={isFormOpen}
            onOpenChange={handleOpenChange}
            unitSize={selectedRecord}
            onSuccess={handleSuccess}
          />
        </div>
        <div className="rounded-md border overflow-hidden">
          <AdminTable
            data={unitSizes}
            columns={columns}
            onEdit={handleEdit}
            isLoading={isLoading}
          />
        </div>
      </AdminPageLayout>
    );
}
