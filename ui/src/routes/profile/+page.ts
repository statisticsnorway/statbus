// src/routes/profile/+page.ts
import { redirect } from '@sveltejs/kit'

export const load = async ({ parent }) => {
  const { supabase, session } = await parent()
  if (!session) {
    throw redirect(303, '/')
  }
  const { data: activity_categories } = await supabase.from('activity_category').select('*')

  return {
    user: session.user,
    activity_categories,
  }
}