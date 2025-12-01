'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  useSubscriptionContextOptional,
  type SubscriptionContextType,
} from '@/contexts/subscription-context'
import {
  SubscriptionInfo,
  SubscriptionPlan,
  PlanFeatures,
  createSubscriptionInfo,
  getPlanFeatures,
  hasFeature,
  canCreateProject,
  getRemainingProjects,
  isSubscriptionActive,
  isTrialExpired,
  getTrialDaysRemaining,
  getRequiredPlanForFeature,
} from '@/lib/subscription'

interface UseSubscriptionReturn {
  loading: boolean
  subscription: SubscriptionInfo | null
  features: PlanFeatures
  isActive: boolean
  isTrialExpired: boolean
  trialDaysRemaining: number
  hasFeature: (feature: keyof PlanFeatures) => boolean
  canCreateProject: () => boolean
  remainingProjects: number | null
  requiredPlanFor: (feature: keyof PlanFeatures) => SubscriptionPlan | null
  refresh: () => Promise<void>
}

/**
 * Hook for accessing subscription data.
 *
 * If used within a SubscriptionProvider, it will use the context data.
 * Otherwise, it will fetch the data directly from Supabase.
 *
 * For most dashboard pages, the SubscriptionProvider is available
 * and this hook will use the pre-loaded context data for better performance.
 */
export function useSubscription(): UseSubscriptionReturn {
  const context = useSubscriptionContextOptional()

  // If context is available, use it
  if (context) {
    return useSubscriptionFromContext(context)
  }

  // Otherwise, fall back to direct fetching
  return useSubscriptionDirect()
}

/**
 * Use subscription data from context (faster, uses pre-loaded data)
 */
function useSubscriptionFromContext(context: SubscriptionContextType): UseSubscriptionReturn {
  const {
    loading,
    subscription: contextSub,
    features,
    isActive,
    isTrialExpired: trialExpired,
    trialDaysRemaining,
    canUseFeature,
    canAddMore,
    getRequiredPlan,
    refreshSubscription,
    usage,
  } = context

  // Convert context subscription to SubscriptionInfo format for backward compatibility
  const subscription: SubscriptionInfo | null = contextSub
    ? {
        plan: contextSub.plan,
        status: contextSub.status,
        projectLimit: features.projectLimit,
        projectsUsed: usage.projects.current,
        trialEndsAt: contextSub.trialEndsAt,
        periodEnd: contextSub.currentPeriodEnd,
        cancelAtPeriodEnd: contextSub.cancelAtPeriodEnd,
      }
    : null

  return {
    loading,
    subscription,
    features,
    isActive,
    isTrialExpired: trialExpired,
    trialDaysRemaining: trialDaysRemaining ?? 0,
    hasFeature: canUseFeature,
    canCreateProject: () => canAddMore('projects'),
    remainingProjects: usage.projects.unlimited ? null : usage.projects.remaining,
    requiredPlanFor: getRequiredPlan,
    refresh: refreshSubscription,
  }
}

/**
 * Direct subscription fetching (fallback when context is not available)
 */
function useSubscriptionDirect(): UseSubscriptionReturn {
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const [subscription, setSubscription] = useState<SubscriptionInfo | null>(null)

  const loadSubscription = async () => {
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      // Get showroom ID
      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user.id)
        .single()

      if (!showroomUser) {
        setLoading(false)
        return
      }

      // Load showroom subscription data
      const { data: showroom } = await supabase
        .from('showrooms')
        .select(
          'subscription_status, subscription_plan, project_count_this_period, trial_ends_at, current_period_end, cancel_at_period_end'
        )
        .eq('id', showroomUser.showroom_id)
        .single()

      if (showroom) {
        setSubscription(createSubscriptionInfo(showroom))
      }
    } catch (error) {
      console.error('Error loading subscription:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadSubscription()
  }, [])

  const plan = subscription?.plan || null
  const features = getPlanFeatures(plan)

  return {
    loading,
    subscription,
    features,
    isActive: subscription ? isSubscriptionActive(subscription.status) : false,
    isTrialExpired: subscription
      ? isTrialExpired(subscription.status, subscription.trialEndsAt)
      : false,
    trialDaysRemaining: subscription
      ? getTrialDaysRemaining(subscription.trialEndsAt)
      : 0,
    hasFeature: (feature: keyof PlanFeatures) => hasFeature(plan, feature),
    canCreateProject: () =>
      subscription
        ? canCreateProject(plan, subscription.projectsUsed)
        : false,
    remainingProjects: subscription
      ? getRemainingProjects(plan, subscription.projectsUsed)
      : 0,
    requiredPlanFor: (feature: keyof PlanFeatures) =>
      getRequiredPlanForFeature(feature),
    refresh: loadSubscription,
  }
}
