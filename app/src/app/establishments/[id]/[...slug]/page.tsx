import { redirect, RedirectType } from "next/navigation";

export default function Fallback({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  redirect(`/establishments/${id}`, RedirectType.replace);
}
