import { useBaseData } from "@/atoms/base-data";
import { Tables } from "@/lib/database.types";
import { useState } from "react";

export function useUserForm() {
  const { refreshBaseData } = useBaseData();
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [selectedUser, setSelectedUser] = useState<Tables<"user"> | null>(null);
  const [formKey, setFormKey] = useState(0);

  const handleOpenChange = (open: boolean) => {
    setIsFormOpen(open);
    if (!open) {
      setFormKey((prevKey) => prevKey + 1);
    }
  };

  const handleSuccess = () => {
    // refresh baseData after a successful create or update of a user
    refreshBaseData();
  };

  const handleCreateUser = () => {
    setSelectedUser(null)
    setIsFormOpen(true)
  }

  const handleEditUser = (user: any) => {
    setSelectedUser(user)
    setIsFormOpen(true)
  }

  return {
    isFormOpen,
    formKey,
    selectedUser,
    handleOpenChange,
    handleSuccess,
    handleCreateUser,
    handleEditUser
  }
}
