import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

export default async function DesignerLayout({
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

  // Check if user is an active designer
  const { data: designer } = await supabase
    .from('designers')
    .select('id, is_active')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .single()

  // If not a designer, redirect to login
  if (!designer) {
    redirect('/login')
  }

  return <>{children}</>
}
