"use client";

import { usePermission } from "@/atoms/auth";
import { Button } from "@/components/ui/button";

type EditButtonProps = React.ComponentProps<typeof Button>;

export const EditButton = (props: EditButtonProps) => {
  const { canEdit } = usePermission();

    if (!canEdit) {
      return null;
    }

  return (
    <Button variant="ghost" type="button" {...props}>
      {props.children}
    </Button>
  );
};
