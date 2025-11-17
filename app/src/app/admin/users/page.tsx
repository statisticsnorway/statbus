"use client";
import { useBaseData } from "@/atoms/base-data";
import UsersTable from "./user-table";
import { UserForm } from "./user-form";
import { useState } from "react";
import { Tables } from "@/lib/database.types";
import { Button } from "@/components/ui/button";
import { Users } from "lucide-react";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { userRoles } from "./roles";

export default function UsersPage() {
  const { statbusUsers, refreshBaseData } = useBaseData();
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [selectedUser, setSelectedUser] = useState<Tables<"user"> | null>(null);
  const [formKey, setFormKey] = useState(0);
  const [searchQuery, setSearchQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState("all");

  const handleOpenChange = (open: boolean) => {
    setIsFormOpen(open);
    if (!open) {
      setFormKey((prevKey) => prevKey + 1);
    }
  };

  const handleSuccess = () => {
    // refresh baseData after a successful update or creating of a user
    refreshBaseData();
  };

  const filteredUsers = statbusUsers.filter((user) => {
    const nameMatch = user.display_name
      ?.toLowerCase()
      .includes(searchQuery.toLowerCase());
    const roleMatch = roleFilter === "all" || user.statbus_role === roleFilter;
    return nameMatch && roleMatch;
  });

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <h1 className="text-center mb-3 text-xl lg:text-2xl">Users</h1>
      <p className="mb-12 text-center">
        View, create and manage user accounts and permissions
      </p>
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
        <Button
          onClick={() => {
            setIsFormOpen(true);
            setSelectedUser(null);
          }}
        >
          <Users className="w-4 h-4" />
          Create new user
        </Button>
        <UserForm
          key={formKey}
          isOpen={isFormOpen}
          onOpenChange={handleOpenChange}
          user={selectedUser}
          onSuccess={handleSuccess}
        />
      </div>
      <div className="rounded-md border overflow-hidden">
        <UsersTable
          users={filteredUsers}
          onEdit={(user) => {
            setSelectedUser(user);
            setIsFormOpen(true);
          }}
        />
      </div>
    </main>
  );
}
