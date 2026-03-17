"use client";
import { useBaseData } from "@/atoms/base-data";
import { UserForm } from "./user-form";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { UserPlus } from "lucide-react";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { userRoles } from "./roles";
import AdminPageLayout from "../page-layout";
import AdminTable, { ColumnDefinition } from "../admin-table";
import { Tables } from "@/lib/database.types";
import { format, formatDistanceToNow } from "date-fns";
import { useAdminForm } from "../use-admin-form";

function formatDateOrTimeAgo(dateString?: string | null) {
  if (!dateString) return "";
  const date = new Date(dateString);

  const daysDiff = Math.abs(
    (new Date().getTime() - date.getTime()) / (1000 * 60 * 60 * 24)
  );

  if (daysDiff < 1) return formatDistanceToNow(date, { addSuffix: true });
  return format(date, "d MMM yyyy 'at' HH:mm");
}

const columns: ColumnDefinition<Tables<"user">>[] = [
  {
    key: "display_name",
    header: "User",
    render: (record) => (
      <div className="flex flex-col">
        <span className="font-medium">{record.display_name}</span>
        <small className="flex text-gray-700">{record.email}</small>
      </div>
    ),
  },
  {
    key: "statbus_role",
    header: "Role",
    render: (record) =>
      record.statbus_role &&
      userRoles.find((r) => r.value === record.statbus_role)?.label,
  },
  {
    key: "created_at",
    header: "Created",
    render: (record) => formatDateOrTimeAgo(record.created_at),
  },
  {
    key: "last_sign_in_at",
    header: "Last signed in",
    render: (record) => formatDateOrTimeAgo(record.last_sign_in_at),
  },
];


export default function UsersPage() {
  const { statbusUsers, refreshBaseData, loading } = useBaseData();
  const {
    isFormOpen,
    handleCreate,
    handleEdit,
    selectedRecord,
    formKey,
    handleOpenChange,
    handleSuccess,
  } = useAdminForm<Tables<"user">>({
    onSuccess: refreshBaseData,
  });
  const [searchQuery, setSearchQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState("all");

  const filteredUsers = statbusUsers.filter((user) => {
    const nameMatch = user.display_name
      ?.toLowerCase()
      .includes(searchQuery.toLowerCase());
    const roleMatch = roleFilter === "all" || user.statbus_role === roleFilter;
    return nameMatch && roleMatch;
  });

  return (
    <AdminPageLayout
      title="Users"
      subtitle="View, create and manage user accounts and permissions"
    >
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <Input
            placeholder="Search by name"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="max-w-sm"
          />
          <Select value={roleFilter} onValueChange={setRoleFilter}>
            <SelectTrigger className="w-[180px]">
              <SelectValue placeholder="Filter by role" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Roles</SelectItem>
              {userRoles.map((role) => (
                <SelectItem key={role.value} value={role.value}>
                  {role.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <Button onClick={() => handleCreate()}>
          <UserPlus className="w-4 h-4" />
          Create new user
        </Button>
        <UserForm
          key={formKey}
          isOpen={isFormOpen}
          onOpenChange={handleOpenChange}
          user={selectedRecord}
          onSuccess={handleSuccess}
        />
      </div>
      <div className="rounded-md border overflow-hidden">
        <AdminTable
          data={filteredUsers}
          columns={columns}
          onEdit={handleEdit}
          isLoading={loading}
        />
      </div>
    </AdminPageLayout>
  );
}
