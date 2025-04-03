import { redirect, RedirectType } from "next/navigation";

export default async function Fallback(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

  redirect(`/legal-units/${id}`, RedirectType.replace);
}
