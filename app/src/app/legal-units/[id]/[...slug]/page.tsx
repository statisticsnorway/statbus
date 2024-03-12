import { redirect, RedirectType } from "next/navigation";

export default function Fallback({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  redirect(`/legal-units/${id}`, RedirectType.replace);
}
