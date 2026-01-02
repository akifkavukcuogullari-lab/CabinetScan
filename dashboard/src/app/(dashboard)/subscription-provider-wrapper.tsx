'use client'

import { ReactNode } from 'react'
import { SubscriptionProvider } from '@/contexts/subscription-context'
import { UsageWarningBanner } from '@/components/subscription/usage-warning-banner'

interface SubscriptionProviderWrapperProps {
  children: ReactNode
  showroomId: string
  initialData: {
    subscription_status?: string
    subscription_plan?: string | null
    subscription_plan_id?: string | null
    project_count_this_period?: number
    product_count?: number
    storage_used_bytes?: number
    team_member_count?: number
    trial_ends_at?: string | null
    current_period_end?: string | null
    grace_period_ends_at?: string | null
    cancel_at_period_end?: boolean
    subscription_plans?: {
      id?: string
      name?: string
      slug?: string
      project_limit?: number | null
      product_limit?: number | null
      storage_limit_gb?: number | null
      team_member_limit?: number | null
      soft_limit_threshold?: number
      has_webhook_access?: boolean
      has_api_access?: boolean
      has_autocad_export?: boolean
      has_priority_support?: boolean
      has_crm_integration?: boolean
      has_ai_agent?: boolean
      price_monthly?: number | null
      price_yearly?: number | null
    } | null
  } | null
}

/**
 * Client-side wrapper for SubscriptionProvider.
 * This is needed because the provider uses React context which requires 'use client'.
 * The layout.tsx (server component) passes server-fetched data to this wrapper.
 */
export function SubscriptionProviderWrapper({
  children,
  showroomId,
  initialData,
}: SubscriptionProviderWrapperProps) {
  return (
    <SubscriptionProvider showroomId={showroomId} initialData={initialData}>
      {children}
    </SubscriptionProvider>
  )
}

/**
 * Separate component for the usage warning banner.
 * Must be used inside SubscriptionProviderWrapper.
 */
export function SubscriptionWarningBanner() {
  return <UsageWarningBanner />
}
