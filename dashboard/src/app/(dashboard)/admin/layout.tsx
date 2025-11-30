import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createClient()

  // Get current user
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  // Check if user is a super admin
  const { data: admin } = await supabase
    .from('admins')
    .select('id, is_active')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .single()

  // If not a super admin, redirect to showroom dashboard
  if (!admin) {
    redirect('/showroom/projects')
  }

  return <>{children}</>
}
