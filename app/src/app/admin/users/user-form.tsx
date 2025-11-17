"use client";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tables } from "@/lib/database.types";
import { useActionState, useEffect } from "react";
import { updateUser, createUser } from "./update-user-server-action";
import { PasswordInput } from "./password-input";
import { Separator } from "@radix-ui/react-select";
import { FormField } from "@/components/form/form-field";
import { userRoles } from "./roles";
import { SelectField } from "@/components/form/select-field";
import { RoleDescriptionTooltip } from "./role-description-tooltip";

export function UserForm({
  user,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly user: Tables<"user"> | null;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!user;
  const action = isEdit ? updateUser : createUser;
  const [state, formAction] = useActionState(action, null);

  const roleOptions = userRoles.map((role) => ({
    value: role.value,
    label: role.label,
  }));

  useEffect(() => {
    if (state?.status === "success") {
      onSuccess();
      onOpenChange(false);
    }
  }, [state?.status, onOpenChange, onSuccess]);

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <form action={formAction} autoComplete="off">
          {isEdit && user.id && (
            <input type="hidden" name="id" value={user.id} />
          )}
          <DialogHeader>
            <DialogTitle className="text-center">
              {isEdit ? "Edit user" : "Create new user"}
            </DialogTitle>
            <DialogDescription className="mt-1">
              {isEdit
                ? "Update the user's details."
                : "Create a new user for STATBUS."}
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4">
            <Separator />
            <div className="grid gap-2">
              <FormField
                label="Name"
                name="display_name"
                response={state}
                value={isEdit ? user.display_name : ""}
                placeholder="Display Name"
              />
            </div>
            <div className="grid gap-2">
              <FormField
                label="Email"
                name="email"
                response={state}
                value={isEdit ? user.email : ""}
                placeholder="example@email.com"
              />
            </div>
            <div className="grid">
              <SelectField
                name="statbus_role"
                label="Role"
                options={roleOptions}
                value={isEdit ? user.statbus_role : ""}
                placeholder="Select user role"
                response={state}
              />
              <RoleDescriptionTooltip />
            </div>
            <div className="grid gap-2">
              <PasswordInput
                id="password"
                label="Password"
                name="password"
                response={state}
                placeholder={
                  isEdit ? "Leave empty to keep current password" : "Password"
                }
              />
            </div>
            <Separator />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit">
              {isEdit ? "Save changes" : "Create user"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
