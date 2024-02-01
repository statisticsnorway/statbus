'use client';
import {User} from "lucide-react";
import {cn} from "@/lib/utils";

export default function ProfileAvatar({className}: { readonly className?: string }) {
  return (
    <a
      href="/profile"
      className={cn(
        "w-7 h-7 rounded-full flex justify-center items-center uppercase bg-green-200",
        className
      )}
    >
      <User size={16}/>
    </a>
  )
}
