import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Eye, EyeOff } from "lucide-react";
import { useState } from "react";

export function PasswordInput({
  id,
  label,
  name,
  value,
  response,
  placeholder,
}: {
  readonly id: string;
  readonly label: string;
  readonly name: string;
  readonly value?: string | null;
  readonly response: UpdateResponse;
  readonly placeholder: string;
}) {
  const [password, setPassword] = useState(value ?? "");
  const [showPassword, setShowPassword] = useState(false);

  const handleTogglePasswordVisibility = () => {
    setShowPassword(!showPassword);
  };
  const error =
    response?.status === "error"
      ? response.errors?.find((a) => a.path === name)
      : null;
  return (
    <div>
      <Label className="flex flex-col space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
        <div className="relative">
          <Input
            id={id}
            name={name}
            type={showPassword ? "text" : "password"}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="pr-10"
            autoComplete="new-password"
            placeholder={placeholder}
          />
          <span
            title={showPassword ? "Hide password" : "Show password"}
            onClick={handleTogglePasswordVisibility}
            className="absolute inset-y-0 right-0 flex items-center pr-3 text-zinc-500 hover:text-zinc-700"
          >
            {showPassword ? (
              <EyeOff className="h-4 w-4" />
            ) : (
              <Eye className="h-4 w-4" />
            )}
          </span>
        </div>
      </Label>
      {error ? (
        <span className="mt-2 block text-sm text-red-500">
          {error?.message}
        </span>
      ) : null}
    </div>
  );
}
