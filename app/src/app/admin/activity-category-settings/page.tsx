"use client"
import { Tables } from "@/lib/database.types";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { useAdminForm } from "../use-admin-form";
import AdminPageLayout from "../page-layout";
import { useActivityCategorySettings } from "./use-activity-category-settings";
import { ActivityCategorySettingsForm } from "./activity-category-settings-form";
import BooleanBadge from "../boolean-badge";


const columns: ColumnDefinition<Tables<"activity_category_standard">>[] = [
  { key: "name", header: "Name" },
  { key: "code", header: "Code" },
  { key: "description", header: "Description" },
  { key: "code_pattern", header: "Code pattern" },
  {
    key: "enabled",
    header: "Enabled",
    render: (record) => <BooleanBadge value={record.enabled} />,
  },
];

export default function ActivityCategorySettingsPage() {
  const { activityCategorySettings, refreshActivityCategorySettings, isLoading } = useActivityCategorySettings();
  const {
    isFormOpen,
    handleEdit,
    selectedRecord,
    formKey,
    handleOpenChange,
    handleSuccess,
  } = useAdminForm<Tables<"activity_category_standard">>({
    onSuccess: () => {
      refreshActivityCategorySettings();
    },
  });
  return (
    <AdminPageLayout
      title="Activity Category Settings"
      subtitle="View, add and manage activity category settings"
    >
      <div className="flex items-center justify-end mb-2">
        {selectedRecord && (
          <ActivityCategorySettingsForm
            key={formKey}
            isOpen={isFormOpen}
            onOpenChange={handleOpenChange}
            activityCategorySetting={selectedRecord}
            onSuccess={handleSuccess}
          />
        )}
      </div>
      <div className="rounded-md border overflow-hidden">
        <AdminTable
          data={activityCategorySettings}
          columns={columns}
          onEdit={handleEdit}
          isLoading={isLoading}
        />
      </div>
    </AdminPageLayout>
  );
}
