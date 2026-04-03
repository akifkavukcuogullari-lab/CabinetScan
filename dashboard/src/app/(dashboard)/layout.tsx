import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Sidebar } from '@/components/shared/sidebar'
import { SubscriptionProviderWrapper, SubscriptionWarningBanner } from './subscription-provider-wrapper'

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

  // Check if user is showroom owner (must be active)
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('id, full_name, email, showroom_id, showrooms(name)')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .single()

  // Check if user is a designer (must be active)
  const { data: designer } = await supabase
    .from('designers')
    .select('id, full_name, email, avatar_url')
    .eq('user_id', user.id)
    .eq('is_active', true)
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
    : designer
    ? {
        type: 'designer' as const,
        name: designer.full_name as string,
        email: designer.email as string,
        designerId: designer.id as string,
        avatarUrl: (designer.avatar_url as string) ?? null,
      }
    : null

  if (!userInfo) {
    redirect('/login')
  }

  // Fetch subscription data for showroom users
  let subscriptionData = null
  if (userInfo.type === 'showroom') {
    const { data: showroom } = await supabase
      .from('showrooms')
      .select(`
        subscription_status,
        subscription_plan,
        subscription_plan_id,
        project_count_this_period,
        product_count,
        storage_used_bytes,
        team_member_count,
        trial_ends_at,
        current_period_end,
        grace_period_ends_at,
        cancel_at_period_end,
        subscription_plans (
          id,
          name,
          slug,
          project_limit,
          product_limit,
          storage_limit_gb,
          team_member_limit,
          soft_limit_threshold,
          has_webhook_access,
          has_api_access,
          has_autocad_export,
          has_priority_support,
          has_crm_integration,
          has_ai_agent,
          price_monthly,
          price_yearly
        )
      `)
      .eq('id', userInfo.showroomId)
      .single()

    subscriptionData = showroom

    // Check if trial has expired
    const isTrialExpired = showroom?.subscription_status === 'trial' &&
      showroom?.trial_ends_at &&
      new Date(showroom.trial_ends_at) < new Date()

    // Block access for suspended subscriptions (admin action - no self-service)
    if (showroom?.subscription_status === 'suspended') {
      redirect('/account-suspended')
    }

    // For trial expired - redirect to trial-expired page
    if (isTrialExpired) {
      redirect('/trial-expired')
    }

    // For canceled - redirect to account-canceled page
    if (showroom?.subscription_status === 'canceled') {
      redirect('/account-canceled')
    }
  }

  // For admin users, render without subscription provider
  if (userInfo.type === 'admin') {
    return (
      <div className="min-h-screen bg-gray-50">
        <Sidebar userInfo={userInfo} />
        <main className="lg:pl-64">
          <div className="p-6">{children}</div>
        </main>
      </div>
    )
  }

  // For designer users, render without subscription provider
  // Uses theme-aware background to support dark mode toggle
  if (userInfo.type === 'designer') {
    return (
      <div className="min-h-screen bg-background">
        <Sidebar userInfo={userInfo} />
        <main className="lg:pl-64">
          <div className="p-6">{children}</div>
        </main>
      </div>
    )
  }

  // For showroom users, wrap with subscription provider
  return (
    <SubscriptionProviderWrapper
      showroomId={userInfo.showroomId}
      initialData={subscriptionData}
    >
      <div className="min-h-screen bg-gray-50">
        <Sidebar userInfo={userInfo} />
        <main className="lg:pl-64">
          <SubscriptionWarningBanner />
          <div className="p-6">{children}</div>
        </main>
      </div>
    </SubscriptionProviderWrapper>
  )
}
