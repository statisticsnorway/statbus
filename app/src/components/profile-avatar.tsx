"use client";
import { User } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAtomValue } from "jotai"; // Import useAtomValue
import { isAuthenticatedAtom, currentUserAtom } from "@/atoms"; // Import necessary atoms

export default function ProfileAvatar({
  className,
}: {
  readonly className?: string;
}) {
  const isAuthenticated = useAtomValue(isAuthenticatedAtom); // Use derived atom
  const currentUser = useAtomValue(currentUserAtom); // Use derived atom
  
  // If not effectively authenticated (i.e., loading or actually not authenticated), don't show avatar
  if (!isAuthenticated) {
    return null;
  }
  
  // Get the first letter of the email for the avatar
  const initial = currentUser?.email ? currentUser.email[0].toUpperCase() : '';
  
  return (
    <a
      href="/profile"
      aria-label="Profile"
      title={currentUser?.email || 'Profile'}
      className={cn(
        "flex h-7 w-7 items-center justify-center rounded-full bg-green-200 uppercase",
        className
      )}
    >
      {initial ? (
        <span className="text-sm font-medium">{initial}</span>
      ) : (
        <User size={16} />
      )}
    </a>
  );
}
