"use client"
import { Tables } from "@/lib/database.types";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { useDataSources } from "./use-data-sources";
import { useAdminForm } from "../use-admin-form";
import AdminPageLayout from "../page-layout";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { DataSourceForm } from "./data-sources-form";
import BooleanBadge from "../boolean-badge";


const columns: ColumnDefinition<Tables<"data_source">>[] = [
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

export default function DataSourcesPage() {
    const {dataSources, refreshDataSources, isLoading} = useDataSources()
    const {
      isFormOpen,
      handleCreate,
      handleEdit,
      selectedRecord,
      formKey,
      handleOpenChange,
      handleSuccess,
    } = useAdminForm<Tables<"data_source">>({
      onSuccess: () => {
        refreshDataSources();
      },
    });
    
    return (
      <AdminPageLayout
        title="Data Sources"
        subtitle="View, create and manage data sources"
      >
        <div className="flex items-center justify-end mb-2">
          <Button onClick={handleCreate}>
            <Plus className="w-4 h-4" />
            Add new data source
          </Button>
          <DataSourceForm
            key={formKey}
            isOpen={isFormOpen}
            onOpenChange={handleOpenChange}
            dataSource={selectedRecord}
            onSuccess={handleSuccess}
          />
        </div>
        <div className="rounded-md border overflow-hidden">
          <AdminTable
            data={dataSources}
            columns={columns}
            onEdit={handleEdit}
            isLoading={isLoading}
          />
        </div>
      </AdminPageLayout>
    );
}
