import { useState } from "react";

export function useAdminForm<T>({
  onSuccess,
}: {
  readonly onSuccess: () => void;
}) {
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [selectedRecord, setSelectedRecord] = useState<T | null>(null);
  const [formKey, setFormKey] = useState(0);

  const handleOpenChange = (open: boolean) => {
    setIsFormOpen(open);
    if (!open) {
      setFormKey((prevKey) => prevKey + 1);
    }
  };

  const handleSuccess = () => {
    onSuccess();
  };

  const handleCreate = () => {
    setSelectedRecord(null);
    setIsFormOpen(true);
  };

  const handleEdit = (record: T) => {
    setSelectedRecord(record);
    setIsFormOpen(true);
  };

  return {
    isFormOpen,
    formKey,
    selectedRecord,
    handleOpenChange,
    handleSuccess,
    handleCreate,
    handleEdit,
  };
}
