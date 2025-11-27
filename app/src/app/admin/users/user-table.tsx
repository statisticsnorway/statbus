import React from "react";
import {
  Table,
  TableBody,
  TableHeader,
  TableRow,
  TableCell,
  TableHead,
} from "@/components/ui/table";
import { Tables } from "@/lib/database.types";
import { format, formatDistanceToNow } from "date-fns";
import { userRoles } from "./roles";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { Edit2Icon, MoreHorizontal } from "lucide-react";

function formatDateOrTimeAgo(dateString?: string | null) {
  if (!dateString) return "Never";
  const date = new Date(dateString);

  const daysDiff = Math.abs(
    (new Date().getTime() - date.getTime()) / (1000 * 60 * 60 * 24)
  );

  if (daysDiff < 1) return formatDistanceToNow(date, { addSuffix: true });
  return format(date, "d MMM yyyy 'at' HH:mm");
}

export default function UsersTable({
  users,
  onEdit,
}: {
  readonly users: Tables<"user">[];
  readonly onEdit: (user: Tables<"user">) => void;
}) {
  return (
    <Table>
      <TableHeader className="bg-gray-50">
        <TableRow>
          <TableHead>User</TableHead>
          <TableHead>Role</TableHead>
          <TableHead>Created</TableHead>
          <TableHead>Last signed in</TableHead>
          <TableHead></TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {users.map((user) => (
          <TableRow key={user.id}>
            <TableCell className="py-3 lg:w-52">
              <div className="flex flex-col">
                <span className="font-medium">{user.display_name}</span>
                <small className="flex text-gray-700">{user.email}</small>
              </div>
            </TableCell>
            <TableCell className="py-3 lg:w-48">
              {user.statbus_role &&
                userRoles.find((r) => r.value === user.statbus_role)?.label}
            </TableCell>
            <TableCell className="py-3 lg:w-48">
              {formatDateOrTimeAgo(user.created_at)}
            </TableCell>
            <TableCell className="py-3 lg:w-48">
              {formatDateOrTimeAgo(user.last_sign_in_at)}
            </TableCell>
            <TableCell className="text-right">
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    className="inline-block"
                    title="Select action"
                  >
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent className="w-48">
                  <DropdownMenuGroup>
                    <DropdownMenuItem onClick={() => onEdit(user)}>
                      <Edit2Icon className="mr-2 w-4 h-4" />
                      Edit user
                    </DropdownMenuItem>
                  </DropdownMenuGroup>
                </DropdownMenuContent>
              </DropdownMenu>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
