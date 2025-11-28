import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function Home() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  // Check if user is admin
  const { data: admin } = await supabase
    .from('admins')
    .select('id')
    .eq('user_id', user.id)
    .single()

  if (admin) {
    redirect('/admin/showrooms')
  }

  // Check if user is showroom owner
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('id')
    .eq('user_id', user.id)
    .single()

  if (showroomUser) {
    redirect('/showroom/projects')
  }

  // No role assigned
  redirect('/login')
}
