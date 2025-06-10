"use client";
import { User } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/atoms/hooks";

export default function ProfileAvatar({
  className,
}: {
  readonly className?: string;
}) {
  const { isAuthenticated, user } = useAuth();
  
  // If not authenticated, don't show the avatar
  if (!isAuthenticated) {
    return null;
  }
  
  // Get the first letter of the email for the avatar
  const initial = user?.email ? user.email[0].toUpperCase() : '';
  
  return (
    <a
      href="/profile"
      aria-label="Profile"
      title={user?.email || 'Profile'}
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
