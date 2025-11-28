import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Sidebar } from '@/components/shared/sidebar'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
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
    .select('id, full_name, email')
    .eq('user_id', user.id)
    .single()

  // Check if user is showroom owner
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('id, full_name, email, showroom_id, showrooms(name)')
    .eq('user_id', user.id)
    .single()

  const userInfo = admin
    ? { type: 'admin' as const, name: admin.full_name as string, email: admin.email as string }
    : showroomUser
    ? {
        type: 'showroom' as const,
        name: showroomUser.full_name as string,
        email: showroomUser.email as string,
        showroomId: showroomUser.showroom_id as string,
        showroomName: (showroomUser.showrooms as unknown as { name: string })?.name ?? '',
      }
    : null

  if (!userInfo) {
    redirect('/login')
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Sidebar userInfo={userInfo} />
      <main className="lg:pl-64">
        <div className="p-6">{children}</div>
      </main>
    </div>
  )
}
