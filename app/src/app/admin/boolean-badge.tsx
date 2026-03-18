import { Check, X } from "lucide-react";

interface BooleanBadgeProps {
  readonly value: boolean;
}

export default function BooleanBadge({
  value,
}: BooleanBadgeProps) {
  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
        value ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"
      }`}
    >
      {value ? <Check className="w-4 h-4" /> : <X className="w-4 h-4" />}
    </span>
  );
}
