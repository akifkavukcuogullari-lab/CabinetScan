'use client'

import Link from 'next/link'
import { Lock, Check, X, Sparkles, ArrowRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  SubscriptionPlan,
  PlanFeatures,
  featureNames,
  getPlanFeatures,
  getRequiredPlanForFeature,
} from '@/lib/subscription'
import { cn } from '@/lib/utils'

interface UpgradeModalProps {
  isOpen: boolean
  onClose: () => void
  feature: keyof PlanFeatures
  currentPlan: SubscriptionPlan | null
  blockedReason?: 'feature_not_available' | 'limit_reached' | 'trial_expired'
}

// Plan display information
const planInfo: Record<SubscriptionPlan, { name: string; price: string; description: string }> = {
  trial: {
    name: 'Free Trial',
    price: 'Free for 14 days',
    description: 'Try selected plan features',
  },
  starter: {
    name: 'Starter',
    price: '$49/month',
    description: 'Scan-only plan for small showrooms',
  },
  pro: {
    name: 'Pro',
    price: '$149/month',
    description: 'For growing showrooms with product catalogs',
  },
  business: {
    name: 'Business',
    price: '$299/month',
    description: 'For power users with automation needs',
  },
  enterprise: {
    name: 'Enterprise',
    price: 'Custom pricing',
    description: 'Full platform access with dedicated support',
  },
}

// Features to compare between plans (boolean features)
const comparableFeatures: (keyof PlanFeatures)[] = [
  'webhookAccess',
  'apiAccess',
  'autocadExport',
  'prioritySupport',
  'crmIntegration',
  'aiAgent',
]

/**
 * Modal dialog shown when user tries to access a locked feature.
 * Displays plan comparison and upgrade options.
 */
export function UpgradeModal({
  isOpen,
  onClose,
  feature,
  currentPlan,
  blockedReason = 'feature_not_available',
}: UpgradeModalProps) {
  const requiredPlan = getRequiredPlanForFeature(feature)
  const featureName = featureNames[feature]
  const currentPlanInfo = currentPlan ? planInfo[currentPlan] : planInfo.trial
  const requiredPlanInfo = requiredPlan ? planInfo[requiredPlan] : planInfo.pro

  const getBlockedMessage = () => {
    switch (blockedReason) {
      case 'limit_reached':
        return `You've reached the limit for this resource on your current plan.`
      case 'trial_expired':
        return `Your free trial has expired. Subscribe to continue using this feature.`
      case 'feature_not_available':
      default:
        return `${featureName} is not available on your current plan.`
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader className="text-center sm:text-left">
          <div className="mx-auto sm:mx-0 mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-blue-50">
            <Lock className="h-6 w-6 text-blue-600" />
          </div>
          <DialogTitle className="text-xl">Upgrade Required</DialogTitle>
          <DialogDescription className="text-base">{getBlockedMessage()}</DialogDescription>
        </DialogHeader>

        {/* Plan Comparison */}
        <div className="py-4">
          <PlanComparison
            currentPlan={currentPlan}
            requiredPlan={requiredPlan}
            highlightFeature={feature}
          />
        </div>

        <DialogFooter className="flex-col sm:flex-row gap-2">
          <Button variant="outline" onClick={onClose} className="sm:flex-1">
            Maybe Later
          </Button>
          <Button asChild className="sm:flex-1">
            <Link href={`/showroom/billing?upgrade=${requiredPlan || 'pro'}`}>
              <Sparkles className="h-4 w-4 mr-2" />
              Upgrade to {requiredPlanInfo.name}
            </Link>
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/**
 * Plan comparison card showing current vs required plan features.
 */
function PlanComparison({
  currentPlan,
  requiredPlan,
  highlightFeature,
}: {
  currentPlan: SubscriptionPlan | null
  requiredPlan: SubscriptionPlan | null
  highlightFeature: keyof PlanFeatures
}) {
  const current = currentPlan || 'trial'
  const required = requiredPlan || 'pro'
  const currentFeatures = getPlanFeatures(current)
  const requiredFeatures = getPlanFeatures(required)

  return (
    <div className="grid grid-cols-2 gap-4">
      {/* Current Plan */}
      <div className="rounded-lg border border-gray-200 p-4 bg-gray-50">
        <div className="text-sm font-medium text-gray-500 mb-1">Current Plan</div>
        <div className="font-semibold text-lg">{planInfo[current].name}</div>
        <div className="text-sm text-gray-600 mb-3">{planInfo[current].price}</div>
        <FeatureList
          features={currentFeatures}
          highlightFeature={highlightFeature}
          variant="current"
        />
      </div>

      {/* Required Plan */}
      <div className="rounded-lg border-2 border-blue-500 p-4 bg-blue-50/50 relative">
        <div className="absolute -top-2.5 left-3 bg-blue-500 text-white text-xs px-2 py-0.5 rounded-full">
          Recommended
        </div>
        <div className="text-sm font-medium text-blue-600 mb-1">Upgrade to</div>
        <div className="font-semibold text-lg">{planInfo[required].name}</div>
        <div className="text-sm text-gray-600 mb-3">{planInfo[required].price}</div>
        <FeatureList
          features={requiredFeatures}
          highlightFeature={highlightFeature}
          variant="required"
        />
      </div>
    </div>
  )
}

/**
 * Feature list showing which features are available in a plan.
 */
function FeatureList({
  features,
  highlightFeature,
  variant,
}: {
  features: PlanFeatures
  highlightFeature: keyof PlanFeatures
  variant: 'current' | 'required'
}) {
  return (
    <ul className="space-y-1.5">
      {comparableFeatures.map((feature) => {
        const hasFeature = features[feature] === true
        const isHighlighted = feature === highlightFeature

        return (
          <li
            key={feature}
            className={cn(
              'flex items-center gap-2 text-sm',
              isHighlighted && variant === 'required' && 'font-medium text-blue-700',
              isHighlighted && variant === 'current' && !hasFeature && 'text-red-600'
            )}
          >
            {hasFeature ? (
              <Check
                className={cn(
                  'h-4 w-4 flex-shrink-0',
                  isHighlighted && variant === 'required' ? 'text-blue-600' : 'text-green-500'
                )}
              />
            ) : (
              <X
                className={cn(
                  'h-4 w-4 flex-shrink-0',
                  isHighlighted ? 'text-red-500' : 'text-gray-300'
                )}
              />
            )}
            <span className={!hasFeature && !isHighlighted ? 'text-gray-400' : ''}>
              {featureNames[feature]}
            </span>
          </li>
        )
      })}
    </ul>
  )
}

/**
 * Inline upgrade prompt for use in feature cards and other UI elements.
 */
interface UpgradePromptProps {
  feature: keyof PlanFeatures
  reason?: string
  compact?: boolean
}

export function UpgradePrompt({ feature, reason, compact = false }: UpgradePromptProps) {
  const requiredPlan = getRequiredPlanForFeature(feature)
  const featureName = featureNames[feature]

  if (compact) {
    return (
      <div className="flex items-center gap-2 text-sm text-gray-500">
        <Lock className="h-4 w-4" />
        <span>
          Requires{' '}
          <Link href="/showroom/billing" className="text-blue-600 hover:underline font-medium">
            {requiredPlan ? planInfo[requiredPlan].name : 'Pro'} plan
          </Link>
        </span>
      </div>
    )
  }

  return (
    <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center">
      <div className="mx-auto mb-3 flex h-10 w-10 items-center justify-center rounded-full bg-blue-50">
        <Lock className="h-5 w-5 text-blue-600" />
      </div>
      <h3 className="font-medium text-gray-900 mb-1">{featureName}</h3>
      <p className="text-sm text-gray-600 mb-4">
        {reason ||
          `This feature is available on the ${requiredPlan ? planInfo[requiredPlan].name : 'Pro'} plan and above.`}
      </p>
      <Button asChild size="sm">
        <Link href="/showroom/billing">
          Upgrade Plan
          <ArrowRight className="ml-2 h-4 w-4" />
        </Link>
      </Button>
    </div>
  )
}

/**
 * Floating upgrade banner that can be used at the bottom of locked pages.
 */
interface UpgradeBannerProps {
  feature: keyof PlanFeatures
}

export function UpgradeBanner({ feature }: UpgradeBannerProps) {
  const requiredPlan = getRequiredPlanForFeature(feature)
  const featureName = featureNames[feature]

  return (
    <div className="fixed bottom-0 left-0 right-0 bg-gradient-to-r from-blue-600 to-blue-700 text-white py-4 px-6 shadow-lg z-50">
      <div className="max-w-7xl mx-auto flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Sparkles className="h-5 w-5" />
          <div>
            <p className="font-medium">Unlock {featureName}</p>
            <p className="text-sm text-blue-100">
              Available on {requiredPlan ? planInfo[requiredPlan].name : 'Pro'} and above
            </p>
          </div>
        </div>
        <Button variant="secondary" asChild>
          <Link href="/showroom/billing">
            View Plans
            <ArrowRight className="ml-2 h-4 w-4" />
          </Link>
        </Button>
      </div>
    </div>
  )
}
