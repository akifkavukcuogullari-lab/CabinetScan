'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { AlertTriangle, X, TrendingUp } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useSubscriptionContext } from '@/contexts/subscription-context'
import { cn } from '@/lib/utils'

interface UsageWarning {
  resource: string
  label: string
  percentage: number
  current: number
  limit: number | null
  remaining: number | null
}

const resourceLabels: Record<string, string> = {
  projects: 'projects',
  products: 'products',
  storage: 'storage',
  teamMembers: 'team members',
}

/**
 * Banner component that displays warnings when usage is approaching limits.
 * Shows when any resource is at 80%+ usage.
 */
export function UsageWarningBanner() {
  const { usage, loading, isTrialExpired, isTrial, trialDaysRemaining, inGracePeriod, subscription } =
    useSubscriptionContext()
  const [dismissed, setDismissed] = useState(false)

  // Reset dismissed state on page reload (session storage persists only for the session)
  useEffect(() => {
    const dismissedKey = 'usage-warning-dismissed'
    const wasDismissed = sessionStorage.getItem(dismissedKey)
    if (wasDismissed) {
      setDismissed(true)
    }
  }, [])

  const handleDismiss = () => {
    setDismissed(true)
    sessionStorage.setItem('usage-warning-dismissed', 'true')
  }

  // Don't show while loading
  if (loading) return null

  // Check for trial expiration warning (high priority)
  if (isTrial && trialDaysRemaining !== null && trialDaysRemaining <= 3 && !isTrialExpired) {
    return (
      <TrialExpiringBanner
        daysRemaining={trialDaysRemaining}
        onDismiss={handleDismiss}
        dismissed={dismissed}
      />
    )
  }

  // Check for trial expired (highest priority)
  if (isTrialExpired && !inGracePeriod) {
    return <TrialExpiredBanner />
  }

  // Check for grace period warning
  if (inGracePeriod) {
    return <GracePeriodBanner subscription={subscription} />
  }

  // Check for payment past due
  if (subscription?.status === 'past_due') {
    return <PaymentOverdueBanner />
  }

  // Check for usage warnings (lowest priority)
  const warnings: UsageWarning[] = Object.entries(usage)
    .filter(([, data]) => data.warning && !data.unlimited)
    .map(([key, data]) => ({
      resource: key,
      label: resourceLabels[key] || key,
      percentage: Math.round(data.percentage),
      current: data.current,
      limit: data.limit,
      remaining: data.remaining,
    }))

  // Check for exceeded limits
  const exceeded = Object.entries(usage)
    .filter(([, data]) => data.exceeded && !data.unlimited)
    .map(([key, data]) => ({
      resource: key,
      label: resourceLabels[key] || key,
      percentage: 100,
      current: data.current,
      limit: data.limit,
      remaining: 0,
    }))

  // Show exceeded limit banner (red)
  if (exceeded.length > 0 && !dismissed) {
    return (
      <LimitExceededBanner
        exceeded={exceeded}
        onDismiss={handleDismiss}
      />
    )
  }

  // Show warning banner (yellow)
  if (warnings.length > 0 && !dismissed) {
    return (
      <WarningBanner
        warnings={warnings}
        onDismiss={handleDismiss}
      />
    )
  }

  return null
}

// Sub-components for different banner types

function WarningBanner({
  warnings,
  onDismiss,
}: {
  warnings: UsageWarning[]
  onDismiss: () => void
}) {
  const primaryWarning = warnings[0]
  const additionalCount = warnings.length - 1

  return (
    <div className="bg-yellow-50 border-b border-yellow-200 px-4 py-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex-shrink-0">
            <AlertTriangle className="h-5 w-5 text-yellow-600" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-yellow-800">
              Approaching {primaryWarning.label} limit
            </p>
            <p className="text-sm text-yellow-700">
              You&apos;ve used {primaryWarning.percentage}% of your {primaryWarning.label} (
              {primaryWarning.current}/{primaryWarning.limit}).
              {primaryWarning.remaining !== null && primaryWarning.remaining > 0 && (
                <> {primaryWarning.remaining} remaining.</>
              )}
              {additionalCount > 0 && (
                <span className="ml-1">
                  +{additionalCount} more resource{additionalCount > 1 ? 's' : ''} approaching limit.
                </span>
              )}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          <Button
            variant="outline"
            size="sm"
            asChild
            className="bg-white border-yellow-300 text-yellow-800 hover:bg-yellow-100"
          >
            <Link href="/showroom/billing">
              <TrendingUp className="h-4 w-4 mr-1.5" />
              Upgrade Plan
            </Link>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-yellow-600 hover:text-yellow-800 hover:bg-yellow-100"
            onClick={onDismiss}
          >
            <X className="h-4 w-4" />
            <span className="sr-only">Dismiss</span>
          </Button>
        </div>
      </div>
    </div>
  )
}

function LimitExceededBanner({
  exceeded,
  onDismiss,
}: {
  exceeded: UsageWarning[]
  onDismiss: () => void
}) {
  const primaryExceeded = exceeded[0]
  const additionalCount = exceeded.length - 1

  return (
    <div className="bg-red-50 border-b border-red-200 px-4 py-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex-shrink-0">
            <AlertTriangle className="h-5 w-5 text-red-600" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-red-800">
              {primaryExceeded.label.charAt(0).toUpperCase() + primaryExceeded.label.slice(1)} limit
              reached
            </p>
            <p className="text-sm text-red-700">
              You&apos;ve reached your {primaryExceeded.label} limit ({primaryExceeded.current}/
              {primaryExceeded.limit}). Upgrade your plan to add more.
              {additionalCount > 0 && (
                <span className="ml-1">
                  +{additionalCount} more limit{additionalCount > 1 ? 's' : ''} reached.
                </span>
              )}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          <Button
            size="sm"
            asChild
            className="bg-red-600 hover:bg-red-700 text-white"
          >
            <Link href="/showroom/billing">
              <TrendingUp className="h-4 w-4 mr-1.5" />
              Upgrade Now
            </Link>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-red-600 hover:text-red-800 hover:bg-red-100"
            onClick={onDismiss}
          >
            <X className="h-4 w-4" />
            <span className="sr-only">Dismiss</span>
          </Button>
        </div>
      </div>
    </div>
  )
}

function TrialExpiringBanner({
  daysRemaining,
  onDismiss,
  dismissed,
}: {
  daysRemaining: number
  onDismiss: () => void
  dismissed: boolean
}) {
  if (dismissed) return null

  const urgency = daysRemaining <= 1 ? 'red' : 'yellow'
  const bgColor = urgency === 'red' ? 'bg-red-50' : 'bg-yellow-50'
  const borderColor = urgency === 'red' ? 'border-red-200' : 'border-yellow-200'
  const textColor = urgency === 'red' ? 'text-red-800' : 'text-yellow-800'
  const iconColor = urgency === 'red' ? 'text-red-600' : 'text-yellow-600'

  return (
    <div className={cn(bgColor, borderColor, 'border-b px-4 py-3')}>
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex-shrink-0">
            <AlertTriangle className={cn('h-5 w-5', iconColor)} />
          </div>
          <div className="min-w-0">
            <p className={cn('text-sm font-medium', textColor)}>
              {daysRemaining === 0
                ? 'Your trial expires today!'
                : daysRemaining === 1
                ? 'Your trial expires tomorrow!'
                : `Your trial expires in ${daysRemaining} days`}
            </p>
            <p className={cn('text-sm', textColor.replace('800', '700'))}>
              Subscribe now to keep using all Pro features without interruption.
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          <Button
            size="sm"
            asChild
            className={urgency === 'red' ? 'bg-red-600 hover:bg-red-700' : 'bg-yellow-600 hover:bg-yellow-700'}
          >
            <Link href="/showroom/billing">Subscribe Now</Link>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className={cn('h-8 w-8', iconColor, urgency === 'red' ? 'hover:bg-red-100' : 'hover:bg-yellow-100')}
            onClick={onDismiss}
          >
            <X className="h-4 w-4" />
            <span className="sr-only">Dismiss</span>
          </Button>
        </div>
      </div>
    </div>
  )
}

function TrialExpiredBanner() {
  return (
    <div className="bg-red-600 px-4 py-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex-shrink-0">
            <AlertTriangle className="h-5 w-5 text-white" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-white">Your trial has expired</p>
            <p className="text-sm text-red-100">
              Subscribe now to restore access to your account and all features.
            </p>
          </div>
        </div>
        <div className="flex-shrink-0">
          <Button size="sm" variant="secondary" asChild>
            <Link href="/showroom/billing">Subscribe Now</Link>
          </Button>
        </div>
      </div>
    </div>
  )
}

function GracePeriodBanner({
  subscription,
}: {
  subscription: { gracePeriodEndsAt: Date | null } | null
}) {
  const daysRemaining = subscription?.gracePeriodEndsAt
    ? Math.max(
        0,
        Math.ceil(
          (subscription.gracePeriodEndsAt.getTime() - new Date().getTime()) / (1000 * 60 * 60 * 24)
        )
      )
    : 0

  return (
    <div className="bg-orange-50 border-b border-orange-200 px-4 py-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex-shrink-0">
            <AlertTriangle className="h-5 w-5 text-orange-600" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-orange-800">Grace period active</p>
            <p className="text-sm text-orange-700">
              You have {daysRemaining} day{daysRemaining !== 1 ? 's' : ''} remaining in your grace
              period. Subscribe now to avoid service interruption.
            </p>
          </div>
        </div>
        <div className="flex-shrink-0">
          <Button size="sm" asChild className="bg-orange-600 hover:bg-orange-700">
            <Link href="/showroom/billing">Subscribe Now</Link>
          </Button>
        </div>
      </div>
    </div>
  )
}

function PaymentOverdueBanner() {
  return (
    <div className="bg-red-50 border-b border-red-200 px-4 py-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex-shrink-0">
            <AlertTriangle className="h-5 w-5 text-red-600" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-red-800">Payment overdue</p>
            <p className="text-sm text-red-700">
              Your payment is past due. Please update your payment method to avoid service
              interruption.
            </p>
          </div>
        </div>
        <div className="flex-shrink-0">
          <Button size="sm" asChild className="bg-red-600 hover:bg-red-700">
            <Link href="/showroom/billing">Update Payment</Link>
          </Button>
        </div>
      </div>
    </div>
  )
}
