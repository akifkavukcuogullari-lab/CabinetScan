'use client'

import { ReactNode, useState } from 'react'
import Link from 'next/link'
import { Lock, Sparkles, ArrowRight, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { useSubscriptionContext, useSubscriptionContextOptional } from '@/contexts/subscription-context'
import { PlanFeatures, featureNames, getRequiredPlanForFeature } from '@/lib/subscription'
import { UpgradeModal } from './upgrade-modal'

interface FeatureGateProps {
  feature: keyof PlanFeatures
  children: ReactNode
  fallback?: ReactNode
  showUpgradePrompt?: boolean
  loadingFallback?: ReactNode
}

/**
 * Component that gates content based on subscription features.
 * Shows upgrade prompt for locked features.
 *
 * Uses the SubscriptionContext to check feature access.
 */
export function FeatureGate({
  feature,
  children,
  fallback,
  showUpgradePrompt = true,
  loadingFallback,
}: FeatureGateProps) {
  const context = useSubscriptionContextOptional()

  // If no context (e.g., admin user), always show children
  if (!context) {
    return <>{children}</>
  }

  const { loading, canUseFeature, getRequiredPlan, subscription } = context

  // While loading, show loading fallback or skeleton
  if (loading) {
    return loadingFallback || <FeatureGateLoadingSkeleton />
  }

  // If user has the feature, show the children
  if (canUseFeature(feature)) {
    return <>{children}</>
  }

  // If no upgrade prompt is needed, show fallback
  if (!showUpgradePrompt) {
    return fallback || null
  }

  // Show fallback if provided
  if (fallback) {
    return <>{fallback}</>
  }

  // Show default upgrade prompt
  const requiredPlan = getRequiredPlan(feature)
  const featureName = featureNames[feature]
  const currentPlan = subscription?.plan || null

  return (
    <UpgradePromptCard
      feature={feature}
      featureName={featureName}
      requiredPlan={requiredPlan}
      currentPlan={currentPlan}
    />
  )
}

/**
 * Loading skeleton for feature gate
 */
function FeatureGateLoadingSkeleton() {
  return (
    <Card className="border-dashed border-gray-200">
      <CardContent className="p-6">
        <div className="flex flex-col items-center text-center">
          <Skeleton className="h-12 w-12 rounded-full mb-4" />
          <Skeleton className="h-5 w-32 mb-2" />
          <Skeleton className="h-4 w-48 mb-4" />
          <Skeleton className="h-9 w-28" />
        </div>
      </CardContent>
    </Card>
  )
}

/**
 * Upgrade prompt card shown when feature is not available
 */
function UpgradePromptCard({
  feature,
  featureName,
  requiredPlan,
  currentPlan,
}: {
  feature: keyof PlanFeatures
  featureName: string
  requiredPlan: string | null
  currentPlan: string | null
}) {
  const [modalOpen, setModalOpen] = useState(false)

  return (
    <>
      <Card className="border-dashed border-gray-300 bg-gray-50">
        <CardHeader className="text-center pb-2">
          <div className="mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-full bg-blue-50">
            <Lock className="h-6 w-6 text-blue-600" />
          </div>
          <CardTitle className="text-lg">{featureName}</CardTitle>
        </CardHeader>
        <CardContent className="text-center">
          <p className="text-sm text-gray-600 mb-4">
            This feature is available on the{' '}
            <span className="font-semibold capitalize">{requiredPlan || 'Pro'}</span> plan
            and above.
          </p>
          <div className="flex flex-col sm:flex-row gap-2 justify-center">
            <Button variant="outline" onClick={() => setModalOpen(true)}>
              Learn More
            </Button>
            <Button asChild>
              <Link href="/showroom/billing">
                <Sparkles className="mr-2 h-4 w-4" />
                Upgrade Plan
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>

      <UpgradeModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        feature={feature}
        currentPlan={currentPlan as 'trial' | 'basic' | 'pro' | 'enterprise' | null}
      />
    </>
  )
}

/**
 * A simpler badge/icon that shows a lock for locked features.
 * Useful for inline feature indicators.
 */
interface FeatureBadgeProps {
  feature: keyof PlanFeatures
  showLabel?: boolean
}

export function FeatureBadge({ feature, showLabel = true }: FeatureBadgeProps) {
  const context = useSubscriptionContextOptional()

  // If no context, don't show badge
  if (!context) return null

  const { canUseFeature, getRequiredPlan } = context

  if (canUseFeature(feature)) {
    return null
  }

  const requiredPlan = getRequiredPlan(feature)

  return (
    <Link
      href="/showroom/billing"
      className="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 text-blue-600 rounded-full text-xs font-medium hover:bg-blue-100 transition-colors"
    >
      <Lock className="h-3 w-3" />
      {showLabel && <span className="capitalize">{requiredPlan || 'Pro'}</span>}
    </Link>
  )
}

/**
 * Hook-based conditional rendering helper.
 * Returns null if feature is locked, otherwise renders children.
 */
interface RequireFeatureProps {
  feature: keyof PlanFeatures
  children: ReactNode
}

export function RequireFeature({ feature, children }: RequireFeatureProps) {
  const context = useSubscriptionContextOptional()

  // If no context, show children (e.g., for admin)
  if (!context) return <>{children}</>

  const { loading, canUseFeature } = context

  if (loading) return null
  if (!canUseFeature(feature)) return null

  return <>{children}</>
}

/**
 * Shows content only if the user's subscription is active.
 */
interface RequireActiveSubscriptionProps {
  children: ReactNode
  fallback?: ReactNode
}

export function RequireActiveSubscription({
  children,
  fallback,
}: RequireActiveSubscriptionProps) {
  const context = useSubscriptionContextOptional()

  // If no context, show children
  if (!context) return <>{children}</>

  const { loading, isActive } = context

  if (loading) return null
  if (!isActive) return fallback || null

  return <>{children}</>
}

/**
 * Limit gate component - blocks content when a usage limit is reached.
 */
interface LimitGateProps {
  resource: 'projects' | 'products' | 'storage' | 'teamMembers'
  children: ReactNode
  fallback?: ReactNode
}

export function LimitGate({ resource, children, fallback }: LimitGateProps) {
  const context = useSubscriptionContextOptional()

  // If no context, show children
  if (!context) return <>{children}</>

  const { loading, canAddMore, usage } = context

  if (loading) return null

  if (!canAddMore(resource)) {
    const resourceLabels: Record<string, string> = {
      projects: 'projects',
      products: 'products',
      storage: 'storage',
      teamMembers: 'team members',
    }
    const metric = usage[resource]

    return (
      fallback || (
        <Card className="border-dashed border-red-300 bg-red-50">
          <CardContent className="p-6 text-center">
            <div className="mx-auto mb-3 flex h-10 w-10 items-center justify-center rounded-full bg-red-100">
              <Lock className="h-5 w-5 text-red-600" />
            </div>
            <h3 className="font-medium text-red-900 mb-1">
              {resourceLabels[resource].charAt(0).toUpperCase() +
                resourceLabels[resource].slice(1)}{' '}
              limit reached
            </h3>
            <p className="text-sm text-red-700 mb-4">
              You&apos;ve used {metric.current} of {metric.limit} {resourceLabels[resource]}.
              Upgrade your plan to add more.
            </p>
            <Button asChild className="bg-red-600 hover:bg-red-700">
              <Link href="/showroom/billing">
                <ArrowRight className="mr-2 h-4 w-4" />
                Upgrade Plan
              </Link>
            </Button>
          </CardContent>
        </Card>
      )
    )
  }

  return <>{children}</>
}

/**
 * Usage meter component - shows current usage vs limit
 */
interface UsageMeterProps {
  resource: 'projects' | 'products' | 'storage' | 'teamMembers'
  label?: string
  showUpgrade?: boolean
}

export function UsageMeter({ resource, label, showUpgrade = true }: UsageMeterProps) {
  const context = useSubscriptionContextOptional()

  if (!context) return null

  const { loading, usage } = context
  const metric = usage[resource]

  if (loading) {
    return <Skeleton className="h-4 w-full" />
  }

  const resourceLabels: Record<string, string> = {
    projects: 'Projects',
    products: 'Products',
    storage: 'Storage (GB)',
    teamMembers: 'Team members',
  }

  const displayLabel = label || resourceLabels[resource]

  if (metric.unlimited) {
    return (
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-600">{displayLabel}</span>
        <span className="text-gray-900 font-medium">{metric.current} (Unlimited)</span>
      </div>
    )
  }

  const percentage = Math.min(100, metric.percentage)
  const barColor = metric.exceeded
    ? 'bg-red-500'
    : metric.warning
    ? 'bg-yellow-500'
    : 'bg-blue-500'

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-600">{displayLabel}</span>
        <span className="text-gray-900 font-medium">
          {metric.current} / {metric.limit}
        </span>
      </div>
      <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
        <div
          className={`h-full ${barColor} transition-all duration-300`}
          style={{ width: `${percentage}%` }}
        />
      </div>
      {metric.exceeded && showUpgrade && (
        <p className="text-xs text-red-600">
          Limit reached.{' '}
          <Link href="/showroom/billing" className="underline font-medium">
            Upgrade plan
          </Link>
        </p>
      )}
      {metric.warning && !metric.exceeded && (
        <p className="text-xs text-yellow-600">
          Approaching limit ({metric.remaining} remaining)
        </p>
      )}
    </div>
  )
}
