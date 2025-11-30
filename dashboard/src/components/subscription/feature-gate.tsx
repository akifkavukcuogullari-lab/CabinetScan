'use client'

import { ReactNode } from 'react'
import Link from 'next/link'
import { Lock, Sparkles } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useSubscription } from '@/hooks/use-subscription'
import { PlanFeatures, featureNames } from '@/lib/subscription'

interface FeatureGateProps {
  feature: keyof PlanFeatures
  children: ReactNode
  fallback?: ReactNode
  showUpgradePrompt?: boolean
}

/**
 * Component that gates content based on subscription features.
 * Shows upgrade prompt for locked features.
 */
export function FeatureGate({
  feature,
  children,
  fallback,
  showUpgradePrompt = true,
}: FeatureGateProps) {
  const { loading, hasFeature, requiredPlanFor } = useSubscription()

  // While loading, show nothing or a placeholder
  if (loading) {
    return fallback || null
  }

  // If user has the feature, show the children
  if (hasFeature(feature)) {
    return <>{children}</>
  }

  // If no upgrade prompt is needed, show fallback
  if (!showUpgradePrompt) {
    return fallback || null
  }

  // Show upgrade prompt
  const requiredPlan = requiredPlanFor(feature)
  const featureName = featureNames[feature]

  return (
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
          <span className="font-semibold capitalize">{requiredPlan}</span> plan
          and above.
        </p>
        <Button asChild>
          <Link href="/showroom/billing">
            <Sparkles className="mr-2 h-4 w-4" />
            Upgrade Plan
          </Link>
        </Button>
      </CardContent>
    </Card>
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
  const { hasFeature, requiredPlanFor } = useSubscription()

  if (hasFeature(feature)) {
    return null
  }

  const requiredPlan = requiredPlanFor(feature)

  return (
    <Link
      href="/showroom/billing"
      className="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 text-blue-600 rounded-full text-xs font-medium hover:bg-blue-100 transition-colors"
    >
      <Lock className="h-3 w-3" />
      {showLabel && <span className="capitalize">{requiredPlan}</span>}
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
  const { loading, hasFeature } = useSubscription()

  if (loading) return null
  if (!hasFeature(feature)) return null

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
  const { loading, isActive } = useSubscription()

  if (loading) return null
  if (!isActive) return fallback || null

  return <>{children}</>
}
