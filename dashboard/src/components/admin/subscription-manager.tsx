'use client'

import { useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import {
  Loader2,
  Save,
  Clock,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Ban,
  Zap,
  Crown,
  Briefcase,
  Building2,
  CalendarPlus,
  Power,
  ShieldOff,
  Check,
  CreditCard,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'

interface SubscriptionManagerProps {
  showroom: {
    id: string
    name: string
    subscription_status: string
    subscription_plan: string | null
    trial_ends_at: string | null
    stripe_customer_id: string | null
    stripe_subscription_id: string | null
  }
}

// Status configuration - clear, distinct meanings
const statusConfig = {
  trial: {
    label: 'Trial',
    description: 'Free trial with Pro features',
    icon: Clock,
    color: 'bg-amber-50 border-amber-200 text-amber-700',
    badgeColor: 'bg-amber-100 text-amber-800 border-amber-200',
  },
  active: {
    label: 'Active',
    description: 'Paid subscription active',
    icon: CheckCircle2,
    color: 'bg-emerald-50 border-emerald-200 text-emerald-700',
    badgeColor: 'bg-emerald-100 text-emerald-800 border-emerald-200',
  },
  past_due: {
    label: 'Past Due',
    description: 'Payment failed, grace period',
    icon: AlertTriangle,
    color: 'bg-orange-50 border-orange-200 text-orange-700',
    badgeColor: 'bg-orange-100 text-orange-800 border-orange-200',
  },
  canceled: {
    label: 'Canceled',
    description: 'Subscription ended',
    icon: XCircle,
    color: 'bg-gray-50 border-gray-200 text-gray-600',
    badgeColor: 'bg-gray-100 text-gray-700 border-gray-200',
  },
  suspended: {
    label: 'Suspended',
    description: 'Account access blocked',
    icon: Ban,
    color: 'bg-red-50 border-red-200 text-red-700',
    badgeColor: 'bg-red-100 text-red-800 border-red-200',
  },
} as const

type StatusKey = keyof typeof statusConfig

// Plan configuration with features - NO trial plan
const planConfig = {
  starter: {
    label: 'Starter',
    price: '$49/mo',
    icon: Zap,
    color: 'border-blue-200 hover:border-blue-400',
    selectedColor: 'border-blue-500 bg-blue-50 ring-2 ring-blue-200',
    features: [
      '20 projects/month',
      '3D room scanning',
      'Floor plans & measurements',
      '5 GB storage',
      'Email support',
    ],
    limits: { projects: 20, products: 0 },
  },
  pro: {
    label: 'Pro',
    price: '$149/mo',
    icon: Crown,
    color: 'border-purple-200 hover:border-purple-400',
    selectedColor: 'border-purple-500 bg-purple-50 ring-2 ring-purple-200',
    popular: true,
    features: [
      '100 projects/month',
      '100 products',
      'Product selection in app',
      'AutoCAD/DXF export',
      'Custom branding',
      'Priority support',
    ],
    limits: { projects: 100, products: 100 },
  },
  business: {
    label: 'Business',
    price: '$249/mo',
    icon: Briefcase,
    color: 'border-orange-200 hover:border-orange-400',
    selectedColor: 'border-orange-500 bg-orange-50 ring-2 ring-orange-200',
    features: [
      'Unlimited projects',
      '300 products',
      'API & Webhook access',
      'AI-generated quotes',
      'Email quotes to customers',
      '100 GB storage',
    ],
    limits: { projects: -1, products: 300 },
  },
  enterprise: {
    label: 'Enterprise',
    price: 'Custom',
    icon: Building2,
    color: 'border-gray-200 hover:border-gray-400',
    selectedColor: 'border-gray-700 bg-gray-50 ring-2 ring-gray-300',
    features: [
      'Everything in Business',
      'Unlimited products',
      'Unlimited storage',
      'CRM integration',
      'White-label solution',
      'Dedicated account manager',
    ],
    limits: { projects: -1, products: -1 },
  },
} as const

type PlanKey = keyof typeof planConfig

export function SubscriptionManager({ showroom }: SubscriptionManagerProps) {
  const router = useRouter()
  const supabase = createClient()

  // Form state
  const [status, setStatus] = useState<StatusKey>(showroom.subscription_status as StatusKey)
  const [plan, setPlan] = useState<PlanKey>((showroom.subscription_plan as PlanKey) || 'pro')
  const [trialEndsAt, setTrialEndsAt] = useState(
    showroom.trial_ends_at
      ? new Date(showroom.trial_ends_at).toISOString().split('T')[0]
      : ''
  )

  // UI state
  const [saving, setSaving] = useState(false)
  const [confirmDialog, setConfirmDialog] = useState<{
    open: boolean
    action: 'suspend' | 'activate' | 'extend' | 'save' | null
    title: string
    description: string
  }>({ open: false, action: null, title: '', description: '' })

  // Detect changes
  const originalPlan = (showroom.subscription_plan as PlanKey) || 'pro'
  const originalTrialDate = showroom.trial_ends_at
    ? new Date(showroom.trial_ends_at).toISOString().split('T')[0]
    : ''

  const hasChanges =
    status !== showroom.subscription_status ||
    plan !== originalPlan ||
    (status === 'trial' && trialEndsAt !== originalTrialDate)

  // Calculate trial info
  const trialDaysRemaining = trialEndsAt
    ? Math.ceil((new Date(trialEndsAt).getTime() - Date.now()) / (1000 * 60 * 60 * 24))
    : null

  // Save handler
  const handleSave = useCallback(async () => {
    setSaving(true)

    try {
      const updates: Record<string, unknown> = {
        subscription_status: status,
        subscription_plan: plan,
      }

      if (status === 'trial' && trialEndsAt) {
        updates.trial_ends_at = new Date(trialEndsAt).toISOString()
      } else if (status !== 'trial') {
        updates.trial_ends_at = null
      }

      const { error } = await supabase
        .from('showrooms')
        .update(updates)
        .eq('id', showroom.id)

      if (error) throw error

      toast.success('Subscription updated', {
        description: `${showroom.name} is now on ${planConfig[plan].label} (${statusConfig[status].label})`,
      })
      router.refresh()
    } catch (err) {
      console.error('Failed to update subscription:', err)
      toast.error('Failed to update subscription', {
        description: 'Please try again or contact support if the issue persists.',
      })
    } finally {
      setSaving(false)
      setConfirmDialog({ open: false, action: null, title: '', description: '' })
    }
  }, [status, plan, trialEndsAt, showroom.id, showroom.name, supabase, router])

  // Quick action: Extend Trial by 7 days
  const handleExtendTrial = useCallback(async () => {
    setSaving(true)

    try {
      const currentEnd = trialEndsAt ? new Date(trialEndsAt) : new Date()
      const newEnd = new Date(currentEnd)
      newEnd.setDate(newEnd.getDate() + 7)

      const { error } = await supabase
        .from('showrooms')
        .update({
          subscription_status: 'trial',
          trial_ends_at: newEnd.toISOString(),
        })
        .eq('id', showroom.id)

      if (error) throw error

      setStatus('trial')
      setTrialEndsAt(newEnd.toISOString().split('T')[0])

      toast.success('Trial extended', {
        description: `Trial now ends on ${newEnd.toLocaleDateString()}`,
      })
      router.refresh()
    } catch (err) {
      console.error('Failed to extend trial:', err)
      toast.error('Failed to extend trial')
    } finally {
      setSaving(false)
      setConfirmDialog({ open: false, action: null, title: '', description: '' })
    }
  }, [trialEndsAt, showroom.id, supabase, router])

  // Quick action: Activate subscription
  const handleActivate = useCallback(async () => {
    setSaving(true)

    try {
      const { error } = await supabase
        .from('showrooms')
        .update({
          subscription_status: 'active',
          trial_ends_at: null,
        })
        .eq('id', showroom.id)

      if (error) throw error

      setStatus('active')
      setTrialEndsAt('')

      toast.success('Subscription activated', {
        description: `${showroom.name} is now active on the ${planConfig[plan].label} plan`,
      })
      router.refresh()
    } catch (err) {
      console.error('Failed to activate subscription:', err)
      toast.error('Failed to activate subscription')
    } finally {
      setSaving(false)
      setConfirmDialog({ open: false, action: null, title: '', description: '' })
    }
  }, [showroom.id, showroom.name, plan, supabase, router])

  // Quick action: Suspend account
  const handleSuspend = useCallback(async () => {
    setSaving(true)

    try {
      const { error } = await supabase
        .from('showrooms')
        .update({
          subscription_status: 'suspended',
        })
        .eq('id', showroom.id)

      if (error) throw error

      setStatus('suspended')

      toast.success('Account suspended', {
        description: `${showroom.name} has been suspended`,
      })
      router.refresh()
    } catch (err) {
      console.error('Failed to suspend account:', err)
      toast.error('Failed to suspend account')
    } finally {
      setSaving(false)
      setConfirmDialog({ open: false, action: null, title: '', description: '' })
    }
  }, [showroom.id, showroom.name, supabase, router])

  // Open confirmation dialog
  const openConfirmDialog = (action: 'suspend' | 'activate' | 'extend' | 'save') => {
    const dialogConfig = {
      suspend: {
        title: 'Suspend Account',
        description: `Are you sure you want to suspend ${showroom.name}? They will lose access to the dashboard and mobile app immediately.`,
      },
      activate: {
        title: 'Activate Subscription',
        description: `Activate ${showroom.name} on the ${planConfig[plan].label} plan? This will remove any trial restrictions.`,
      },
      extend: {
        title: 'Extend Trial',
        description: `Add 7 more days to ${showroom.name}'s trial? Their new trial end date will be ${
          trialEndsAt
            ? new Date(new Date(trialEndsAt).getTime() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString()
            : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString()
        }.`,
      },
      save: {
        title: 'Save Changes',
        description: `Update subscription to ${statusConfig[status].label} status with ${planConfig[plan].label} plan?`,
      },
    }

    setConfirmDialog({
      open: true,
      action,
      ...dialogConfig[action],
    })
  }

  // Handle dialog confirm
  const handleDialogConfirm = () => {
    switch (confirmDialog.action) {
      case 'suspend':
        handleSuspend()
        break
      case 'activate':
        handleActivate()
        break
      case 'extend':
        handleExtendTrial()
        break
      case 'save':
        handleSave()
        break
    }
  }

  // Reset form
  const handleReset = () => {
    setStatus(showroom.subscription_status as StatusKey)
    setPlan(originalPlan)
    setTrialEndsAt(originalTrialDate)
  }

  const currentStatusConfig = statusConfig[showroom.subscription_status as StatusKey] || statusConfig.trial
  const StatusIcon = currentStatusConfig.icon

  return (
    <>
      <Card className="overflow-hidden">
        <CardHeader className="pb-4">
          <div className="flex items-start justify-between">
            <div>
              <CardTitle className="text-xl">Subscription Management</CardTitle>
              <CardDescription className="mt-1">
                Manage plan and billing status for {showroom.name}
              </CardDescription>
            </div>
            <Badge className={currentStatusConfig.badgeColor + ' border'}>
              <StatusIcon className="h-3 w-3 mr-1" />
              {currentStatusConfig.label}
            </Badge>
          </div>
        </CardHeader>

        <CardContent className="space-y-8">
          {/* Current Overview */}
          <div className={`p-4 rounded-lg border-2 ${currentStatusConfig.color} transition-colors duration-300`}>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-full bg-white/80">
                  <StatusIcon className="h-5 w-5" />
                </div>
                <div>
                  <p className="font-semibold">{currentStatusConfig.label}</p>
                  <p className="text-sm opacity-80">{currentStatusConfig.description}</p>
                </div>
              </div>
              {showroom.subscription_status === 'trial' && trialDaysRemaining !== null && (
                <div className="text-right">
                  <p className={`text-2xl font-bold ${trialDaysRemaining <= 3 ? 'text-red-600' : ''}`}>
                    {trialDaysRemaining > 0 ? trialDaysRemaining : 0}
                  </p>
                  <p className="text-sm opacity-80">days left</p>
                </div>
              )}
              {showroom.subscription_plan && (
                <div className="text-right">
                  <p className="font-semibold capitalize">{showroom.subscription_plan}</p>
                  <p className="text-sm opacity-80">
                    {planConfig[showroom.subscription_plan as PlanKey]?.price || ''}
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Quick Actions */}
          <div>
            <Label className="text-sm font-medium text-gray-700 mb-3 block">Quick Actions</Label>
            <div className="flex flex-wrap gap-3">
              <Button
                variant="outline"
                size="sm"
                onClick={() => openConfirmDialog('extend')}
                disabled={saving}
                className="gap-2 hover:bg-amber-50 hover:text-amber-700 hover:border-amber-300 transition-colors"
              >
                <CalendarPlus className="h-4 w-4" />
                Extend Trial (+7 days)
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => openConfirmDialog('activate')}
                disabled={saving || showroom.subscription_status === 'active'}
                className="gap-2 hover:bg-emerald-50 hover:text-emerald-700 hover:border-emerald-300 transition-colors"
              >
                <Power className="h-4 w-4" />
                Activate
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => openConfirmDialog('suspend')}
                disabled={saving || showroom.subscription_status === 'suspended'}
                className="gap-2 hover:bg-red-50 hover:text-red-700 hover:border-red-300 transition-colors"
              >
                <ShieldOff className="h-4 w-4" />
                Suspend
              </Button>
            </div>
          </div>

          <Separator />

          {/* Status Section */}
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <div className="h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center">
                <span className="text-sm font-semibold text-gray-600">1</span>
              </div>
              <div>
                <Label className="text-base font-semibold">Account Status</Label>
                <p className="text-sm text-gray-500">Set the current billing status</p>
              </div>
            </div>

            <Select value={status} onValueChange={(v) => setStatus(v as StatusKey)}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Select status" />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(statusConfig).map(([key, config]) => {
                  const Icon = config.icon
                  return (
                    <SelectItem key={key} value={key}>
                      <div className="flex items-center gap-2">
                        <Icon className="h-4 w-4" />
                        <span className="font-medium">{config.label}</span>
                        <span className="text-gray-500">- {config.description}</span>
                      </div>
                    </SelectItem>
                  )
                })}
              </SelectContent>
            </Select>

            {/* Trial End Date (conditional) */}
            {status === 'trial' && (
              <div className="ml-10 p-4 bg-amber-50 rounded-lg border border-amber-200 space-y-3 animate-in fade-in slide-in-from-top-2 duration-200">
                <Label htmlFor="trialEndsAt" className="text-sm font-medium text-amber-800">
                  Trial End Date
                </Label>
                <Input
                  id="trialEndsAt"
                  type="date"
                  value={trialEndsAt}
                  onChange={(e) => setTrialEndsAt(e.target.value)}
                  min={new Date().toISOString().split('T')[0]}
                  className="bg-white"
                />
                {trialDaysRemaining !== null && (
                  <p className={`text-sm ${trialDaysRemaining <= 3 ? 'text-red-600 font-medium' : 'text-amber-700'}`}>
                    {trialDaysRemaining > 0
                      ? `${trialDaysRemaining} days remaining`
                      : trialDaysRemaining === 0
                      ? 'Expires today'
                      : 'Trial has expired'}
                  </p>
                )}
              </div>
            )}
          </div>

          <Separator />

          {/* Plan Selection */}
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <div className="h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center">
                <span className="text-sm font-semibold text-gray-600">2</span>
              </div>
              <div>
                <Label className="text-base font-semibold">Subscription Plan</Label>
                <p className="text-sm text-gray-500">
                  {status === 'trial'
                    ? 'Plan to activate after trial ends'
                    : 'Current subscription tier'}
                </p>
              </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
              {Object.entries(planConfig).map(([key, config]) => {
                const Icon = config.icon
                const isSelected = plan === key

                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setPlan(key as PlanKey)}
                    className={`
                      relative p-4 rounded-lg border-2 text-left transition-all duration-200
                      ${isSelected ? config.selectedColor : config.color}
                      hover:shadow-md focus:outline-none focus:ring-2 focus:ring-offset-2
                    `}
                  >
                    {'popular' in config && config.popular && (
                      <span className="absolute -top-2.5 left-1/2 -translate-x-1/2 px-2 py-0.5 bg-purple-600 text-white text-xs font-medium rounded-full">
                        Popular
                      </span>
                    )}

                    <div className="flex items-center gap-2 mb-2">
                      <Icon className={`h-5 w-5 ${isSelected ? 'text-current' : 'text-gray-400'}`} />
                      <span className="font-semibold">{config.label}</span>
                      {isSelected && (
                        <Check className="h-4 w-4 ml-auto text-current" />
                      )}
                    </div>

                    <p className="text-lg font-bold mb-3">{config.price}</p>

                    <ul className="space-y-1.5">
                      {config.features.map((feature, i) => (
                        <li key={i} className="flex items-start gap-2 text-sm">
                          <Check className={`h-4 w-4 mt-0.5 flex-shrink-0 ${isSelected ? 'text-current' : 'text-gray-400'}`} />
                          <span className={isSelected ? '' : 'text-gray-600'}>{feature}</span>
                        </li>
                      ))}
                    </ul>
                  </button>
                )
              })}
            </div>
          </div>

          {/* Stripe Info */}
          {(showroom.stripe_customer_id || showroom.stripe_subscription_id) && (
            <>
              <Separator />
              <div className="p-4 bg-gray-50 rounded-lg space-y-3">
                <div className="flex items-center gap-2 text-gray-700">
                  <CreditCard className="h-4 w-4" />
                  <span className="text-sm font-medium">Stripe Integration</span>
                </div>
                <div className="grid gap-2 text-sm">
                  {showroom.stripe_customer_id && (
                    <div className="flex items-center justify-between">
                      <span className="text-gray-500">Customer ID</span>
                      <code className="font-mono text-xs bg-gray-200 px-2 py-1 rounded">
                        {showroom.stripe_customer_id}
                      </code>
                    </div>
                  )}
                  {showroom.stripe_subscription_id && (
                    <div className="flex items-center justify-between">
                      <span className="text-gray-500">Subscription ID</span>
                      <code className="font-mono text-xs bg-gray-200 px-2 py-1 rounded">
                        {showroom.stripe_subscription_id}
                      </code>
                    </div>
                  )}
                </div>
              </div>
            </>
          )}

          <Separator />

          {/* Action Buttons */}
          <div className="flex items-center justify-between pt-2">
            <div className="text-sm text-gray-500">
              {hasChanges ? (
                <span className="flex items-center gap-1.5 text-amber-600">
                  <span className="h-2 w-2 rounded-full bg-amber-500 animate-pulse" />
                  Unsaved changes
                </span>
              ) : (
                <span className="text-gray-400">No changes</span>
              )}
            </div>
            <div className="flex gap-3">
              <Button
                variant="outline"
                onClick={handleReset}
                disabled={!hasChanges || saving}
              >
                Reset
              </Button>
              <Button
                onClick={() => openConfirmDialog('save')}
                disabled={!hasChanges || saving}
                className="gap-2 min-w-[140px]"
              >
                {saving ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Saving...
                  </>
                ) : (
                  <>
                    <Save className="h-4 w-4" />
                    Save Changes
                  </>
                )}
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Confirmation Dialog */}
      <AlertDialog open={confirmDialog.open} onOpenChange={(open) => !open && setConfirmDialog({ ...confirmDialog, open: false })}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{confirmDialog.title}</AlertDialogTitle>
            <AlertDialogDescription>{confirmDialog.description}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={saving}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDialogConfirm}
              disabled={saving}
              className={confirmDialog.action === 'suspend' ? 'bg-red-600 hover:bg-red-700' : ''}
            >
              {saving ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Processing...
                </>
              ) : (
                'Confirm'
              )}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
