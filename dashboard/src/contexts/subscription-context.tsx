'use client'

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  ReactNode,
} from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  SubscriptionPlan,
  SubscriptionStatus,
  PlanFeatures,
  getPlanFeatures,
  hasFeature as checkHasFeature,
  isSubscriptionActive,
  getTrialDaysRemaining,
  getRequiredPlanForFeature,
  featureNames,
} from '@/lib/subscription'

// Usage metrics for each resource type
export interface UsageMetric {
  current: number
  limit: number | null
  percentage: number
  warning: boolean
  unlimited: boolean
  remaining: number | null
  exceeded: boolean
}

export interface UsageMetrics {
  projects: UsageMetric
  products: UsageMetric
  storage: UsageMetric
  teamMembers: UsageMetric
}

// Subscription data from database
export interface SubscriptionData {
  plan: SubscriptionPlan | null
  planId: string | null
  status: SubscriptionStatus
  trialEndsAt: Date | null
  currentPeriodEnd: Date | null
  gracePeriodEndsAt: Date | null
  cancelAtPeriodEnd: boolean
}

// Plan details from subscription_plans table
export interface PlanDetails {
  id: string
  name: string
  slug: string
  projectLimit: number | null
  productLimit: number | null
  storageGb: number | null
  teamMemberLimit: number | null
  softLimitThreshold: number
  hasWebhookAccess: boolean
  hasApiAccess: boolean
  hasAutocadExport: boolean
  hasPrioritySupport: boolean
  hasCrmIntegration: boolean
  hasAiAgent: boolean
  priceMonthly: number | null
  priceYearly: number | null
}

export interface SubscriptionContextType {
  // State
  loading: boolean
  error: string | null
  subscription: SubscriptionData | null
  planDetails: PlanDetails | null
  features: PlanFeatures
  usage: UsageMetrics
  showroomId: string | null

  // Computed
  isActive: boolean
  isTrial: boolean
  isTrialExpired: boolean
  trialDaysRemaining: number | null
  inGracePeriod: boolean

  // Methods
  refreshSubscription: () => Promise<void>
  canUseFeature: (feature: keyof PlanFeatures) => boolean
  canAddMore: (resource: keyof UsageMetrics) => boolean
  getUpgradeReason: (feature: keyof PlanFeatures) => string
  getRequiredPlan: (feature: keyof PlanFeatures) => SubscriptionPlan | null
}

const defaultUsageMetric: UsageMetric = {
  current: 0,
  limit: null,
  percentage: 0,
  warning: false,
  unlimited: true,
  remaining: null,
  exceeded: false,
}

const defaultUsage: UsageMetrics = {
  projects: { ...defaultUsageMetric },
  products: { ...defaultUsageMetric },
  storage: { ...defaultUsageMetric },
  teamMembers: { ...defaultUsageMetric },
}

const SubscriptionContext = createContext<SubscriptionContextType | null>(null)

interface SubscriptionProviderProps {
  children: ReactNode
  showroomId: string | null
  initialData?: {
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

export function SubscriptionProvider({
  children,
  showroomId,
  initialData,
}: SubscriptionProviderProps) {
  const supabase = createClient()
  const [loading, setLoading] = useState(!initialData)
  const [error, setError] = useState<string | null>(null)
  const [subscription, setSubscription] = useState<SubscriptionData | null>(
    initialData ? parseSubscriptionData(initialData) : null
  )
  const [planDetails, setPlanDetails] = useState<PlanDetails | null>(
    initialData?.subscription_plans ? parsePlanDetails(initialData.subscription_plans) : null
  )
  const [usage, setUsage] = useState<UsageMetrics>(
    initialData ? parseUsageMetrics(initialData, initialData.subscription_plans) : defaultUsage
  )

  // Parse subscription data from database format
  function parseSubscriptionData(data: NonNullable<SubscriptionProviderProps['initialData']>): SubscriptionData {
    return {
      plan: (data.subscription_plan as SubscriptionPlan) || null,
      planId: data.subscription_plan_id || null,
      status: (data.subscription_status as SubscriptionStatus) || 'trial',
      trialEndsAt: data.trial_ends_at ? new Date(data.trial_ends_at) : null,
      currentPeriodEnd: data.current_period_end ? new Date(data.current_period_end) : null,
      gracePeriodEndsAt: data.grace_period_ends_at ? new Date(data.grace_period_ends_at) : null,
      cancelAtPeriodEnd: data.cancel_at_period_end || false,
    }
  }

  // Parse plan details from database format
  function parsePlanDetails(data: NonNullable<NonNullable<SubscriptionProviderProps['initialData']>['subscription_plans']>): PlanDetails {
    return {
      id: data.id || '',
      name: data.name || '',
      slug: data.slug || '',
      projectLimit: data.project_limit ?? null,
      productLimit: data.product_limit ?? null,
      storageGb: data.storage_limit_gb ?? null,
      teamMemberLimit: data.team_member_limit ?? null,
      softLimitThreshold: data.soft_limit_threshold ?? 0.8,
      hasWebhookAccess: data.has_webhook_access ?? false,
      hasApiAccess: data.has_api_access ?? false,
      hasAutocadExport: data.has_autocad_export ?? false,
      hasPrioritySupport: data.has_priority_support ?? false,
      hasCrmIntegration: data.has_crm_integration ?? false,
      hasAiAgent: data.has_ai_agent ?? false,
      priceMonthly: data.price_monthly ?? null,
      priceYearly: data.price_yearly ?? null,
    }
  }

  // Parse usage metrics from database format
  function parseUsageMetrics(
    data: NonNullable<SubscriptionProviderProps['initialData']>,
    plan: NonNullable<SubscriptionProviderProps['initialData']>['subscription_plans'] | null
  ): UsageMetrics {
    const threshold = plan?.soft_limit_threshold ?? 0.8

    const createMetric = (current: number, limit: number | null): UsageMetric => {
      const unlimited = limit === null
      const percentage = unlimited ? 0 : limit > 0 ? (current / limit) * 100 : 0
      return {
        current,
        limit,
        percentage: Math.round(percentage * 10) / 10,
        warning: !unlimited && percentage >= threshold * 100 && percentage < 100,
        unlimited,
        remaining: unlimited ? null : Math.max(0, (limit || 0) - current),
        exceeded: !unlimited && current >= (limit || 0),
      }
    }

    // Convert storage bytes to GB for display
    const storageBytes = data.storage_used_bytes || 0
    const storageGb = storageBytes / (1024 * 1024 * 1024)
    const storageLimitGb = plan?.storage_limit_gb ?? null

    return {
      projects: createMetric(data.project_count_this_period || 0, plan?.project_limit ?? null),
      products: createMetric(data.product_count || 0, plan?.product_limit ?? null),
      storage: createMetric(Math.round(storageGb * 100) / 100, storageLimitGb),
      teamMembers: createMetric(data.team_member_count || 1, plan?.team_member_limit ?? null),
    }
  }

  // Load subscription data from database
  const loadSubscription = useCallback(async () => {
    if (!showroomId) {
      setLoading(false)
      return
    }

    setError(null)

    try {
      // Fetch showroom with subscription plan details
      const { data: showroom, error: showroomError } = await supabase
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
        .eq('id', showroomId)
        .single()

      if (showroomError) {
        throw showroomError
      }

      if (showroom) {
        setSubscription(parseSubscriptionData(showroom))
        const planData = showroom.subscription_plans as unknown as NonNullable<SubscriptionProviderProps['initialData']>['subscription_plans']
        setPlanDetails(planData ? parsePlanDetails(planData) : null)
        setUsage(parseUsageMetrics(showroom, planData))
      }
    } catch (err) {
      console.error('Error loading subscription:', err)
      setError('Failed to load subscription data')
    } finally {
      setLoading(false)
    }
  }, [showroomId, supabase])

  // Load data on mount if no initial data
  useEffect(() => {
    if (!initialData && showroomId) {
      loadSubscription()
    }
  }, [initialData, showroomId, loadSubscription])

  // Get features from the plan
  const features = getPlanFeatures(subscription?.plan || null)

  // Computed values
  const isActive = subscription ? isSubscriptionActive(subscription.status) : false

  const isTrial = subscription?.status === 'trial'

  const isTrialExpired = (() => {
    if (!subscription || subscription.status !== 'trial' || !subscription.trialEndsAt) {
      return false
    }
    return new Date() > subscription.trialEndsAt
  })()

  const trialDaysRemaining = subscription?.trialEndsAt
    ? getTrialDaysRemaining(subscription.trialEndsAt)
    : null

  const inGracePeriod = (() => {
    if (!subscription?.gracePeriodEndsAt) return false
    const now = new Date()
    // Check if we're past trial/payment due but within grace period
    if (subscription.status === 'trial' && subscription.trialEndsAt && now > subscription.trialEndsAt) {
      return now <= subscription.gracePeriodEndsAt
    }
    if (subscription.status === 'past_due') {
      return now <= subscription.gracePeriodEndsAt
    }
    return false
  })()

  // Methods
  const canUseFeature = useCallback(
    (feature: keyof PlanFeatures): boolean => {
      // During trial, user gets features from their actual plan
      // If no plan specified, default to Pro features
      if (isTrial && !isTrialExpired) {
        const trialPlan = subscription?.plan || 'pro'
        const planFeatures = getPlanFeatures(trialPlan)
        const value = planFeatures[feature]
        if (typeof value === 'boolean') return value
        return true
      }
      return checkHasFeature(subscription?.plan || null, feature)
    },
    [subscription?.plan, isTrial, isTrialExpired]
  )

  const canAddMore = useCallback(
    (resource: keyof UsageMetrics): boolean => {
      const metric = usage[resource]
      if (metric.unlimited) return true
      return !metric.exceeded
    },
    [usage]
  )

  const getUpgradeReason = useCallback(
    (feature: keyof PlanFeatures): string => {
      const featureName = featureNames[feature]
      const requiredPlan = getRequiredPlanForFeature(feature)

      if (isTrialExpired) {
        return `Your trial has expired. Subscribe to access ${featureName}.`
      }

      if (!isActive) {
        return `Your subscription is not active. Please update your subscription to access ${featureName}.`
      }

      return `${featureName} requires the ${requiredPlan?.charAt(0).toUpperCase()}${requiredPlan?.slice(1)} plan or higher.`
    },
    [isActive, isTrialExpired]
  )

  const getRequiredPlan = useCallback(
    (feature: keyof PlanFeatures): SubscriptionPlan | null => {
      return getRequiredPlanForFeature(feature)
    },
    []
  )

  const contextValue: SubscriptionContextType = {
    loading,
    error,
    subscription,
    planDetails,
    features,
    usage,
    showroomId,
    isActive,
    isTrial,
    isTrialExpired,
    trialDaysRemaining,
    inGracePeriod,
    refreshSubscription: loadSubscription,
    canUseFeature,
    canAddMore,
    getUpgradeReason,
    getRequiredPlan,
  }

  return (
    <SubscriptionContext.Provider value={contextValue}>
      {children}
    </SubscriptionContext.Provider>
  )
}

export function useSubscriptionContext() {
  const context = useContext(SubscriptionContext)
  if (!context) {
    throw new Error('useSubscriptionContext must be used within SubscriptionProvider')
  }
  return context
}

// Optional hook that returns null if outside provider (useful for components that may be used both inside and outside provider)
export function useSubscriptionContextOptional() {
  return useContext(SubscriptionContext)
}
