'use client'

import { useState, useEffect } from 'react'
import { useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  AlertCircle,
  Check,
  CreditCard,
  Download,
  ExternalLink,
  Loader2,
  Sparkles,
  Zap,
  Building2,
  AlertTriangle,
} from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'

interface SubscriptionPlan {
  id: string
  name: string
  slug: string
  price_monthly: number
  price_yearly: number | null
  project_limit: number | null
  storage_limit_gb: number | null
  team_member_limit: number | null
  features: string[]
  has_webhook_access: boolean
  has_api_access: boolean
  has_autocad_export: boolean
  has_priority_support: boolean
  has_crm_integration: boolean
  has_ai_agent: boolean
  description: string | null
  is_featured: boolean
}

interface Invoice {
  id: string
  invoice_number: string
  status: string
  total_cents: number
  currency: string
  period_start: string
  period_end: string
  paid_at: string | null
  invoice_pdf_url: string | null
  hosted_invoice_url: string | null
}

interface Showroom {
  id: string
  name: string
  subscription_status: string
  subscription_plan: string | null
  subscription_plan_id: string | null
  trial_ends_at: string | null
  current_period_end: string | null
  cancel_at_period_end: boolean
  project_count_this_period: number
  stripe_customer_id: string | null
}

export default function BillingPage() {
  const searchParams = useSearchParams()
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [checkoutLoading, setCheckoutLoading] = useState<string | null>(null)
  const [portalLoading, setPortalLoading] = useState(false)
  const [showroomId, setShowroomId] = useState<string | null>(null)
  const [showroom, setShowroom] = useState<Showroom | null>(null)
  const [plans, setPlans] = useState<SubscriptionPlan[]>([])
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [billingPeriod, setBillingPeriod] = useState<'monthly' | 'yearly'>('monthly')
  const [error, setError] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)

  // Check for success/cancel query params
  useEffect(() => {
    if (searchParams.get('success') === 'true') {
      setSuccessMessage('Your subscription has been activated successfully!')
    } else if (searchParams.get('canceled') === 'true') {
      setError('Checkout was canceled. You can try again when ready.')
    }
  }, [searchParams])

  useEffect(() => {
    async function loadData() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()
        if (!user) return

        // Get showroom ID
        const { data: showroomUser } = await supabase
          .from('showroom_users')
          .select('showroom_id')
          .eq('user_id', user.id)
          .single()

        if (!showroomUser) return

        setShowroomId(showroomUser.showroom_id)

        // Load showroom details
        const { data: showroomData } = await supabase
          .from('showrooms')
          .select(
            'id, name, subscription_status, subscription_plan, subscription_plan_id, trial_ends_at, current_period_end, cancel_at_period_end, project_count_this_period, stripe_customer_id'
          )
          .eq('id', showroomUser.showroom_id)
          .single()

        if (showroomData) setShowroom(showroomData)

        // Load subscription plans
        const { data: plansData } = await supabase
          .from('subscription_plans')
          .select('*')
          .eq('is_active', true)
          .order('display_order')

        if (plansData) setPlans(plansData)

        // Load invoices
        const { data: invoicesData } = await supabase
          .from('invoices')
          .select('*')
          .eq('showroom_id', showroomUser.showroom_id)
          .order('created_at', { ascending: false })
          .limit(10)

        if (invoicesData) setInvoices(invoicesData)
      } catch (err) {
        console.error('Error loading billing data:', err)
        setError('Failed to load billing information')
      } finally {
        setLoading(false)
      }
    }

    loadData()
  }, [supabase])

  const handleSubscribe = async (planSlug: string) => {
    if (!showroomId) return

    setCheckoutLoading(planSlug)
    setError(null)

    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!session?.access_token) {
        setError('Please sign in to subscribe')
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/create-checkout-session`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${session.access_token}`,
            apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            showroom_id: showroomId,
            plan_slug: planSlug,
            billing_period: billingPeriod,
          }),
        }
      )

      const data = await response.json()

      if (data.setup_required) {
        setError('Stripe billing is not configured yet. Please contact support.')
        return
      }

      if (data.error) {
        setError(data.message || data.error)
        return
      }

      // Redirect to Stripe Checkout
      if (data.url) {
        window.location.href = data.url
      }
    } catch (err) {
      console.error('Error creating checkout:', err)
      setError('Failed to start checkout. Please try again.')
    } finally {
      setCheckoutLoading(null)
    }
  }

  const handleManageBilling = async () => {
    if (!showroomId) return

    setPortalLoading(true)
    setError(null)

    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!session?.access_token) {
        setError('Please sign in to manage billing')
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/create-portal-session`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${session.access_token}`,
            apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            showroom_id: showroomId,
          }),
        }
      )

      const data = await response.json()

      if (data.setup_required) {
        setError('Stripe billing is not configured yet. Please contact support.')
        return
      }

      if (data.error) {
        setError(data.message || data.error)
        return
      }

      // Redirect to Stripe Customer Portal
      if (data.url) {
        window.location.href = data.url
      }
    } catch (err) {
      console.error('Error opening portal:', err)
      setError('Failed to open billing portal. Please try again.')
    } finally {
      setPortalLoading(false)
    }
  }

  const formatPrice = (cents: number, currency: string = 'usd') => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase(),
    }).format(cents / 100)
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    })
  }

  const getCurrentPlan = () => {
    if (!showroom?.subscription_plan) return null
    return plans.find((p) => p.slug === showroom.subscription_plan)
  }

  const getTrialDaysRemaining = () => {
    if (!showroom?.trial_ends_at) return 0
    const endDate = new Date(showroom.trial_ends_at)
    const now = new Date()
    const diffTime = endDate.getTime() - now.getTime()
    return Math.max(0, Math.ceil(diffTime / (1000 * 60 * 60 * 24)))
  }

  const getPlanIcon = (slug: string) => {
    switch (slug) {
      case 'basic':
        return <Zap className="h-5 w-5" />
      case 'pro':
        return <Sparkles className="h-5 w-5" />
      case 'enterprise':
        return <Building2 className="h-5 w-5" />
      default:
        return <CreditCard className="h-5 w-5" />
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
      </div>
    )
  }

  const currentPlan = getCurrentPlan()
  const trialDays = getTrialDaysRemaining()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Billing & Subscription</h1>
        <p className="text-gray-500">Manage your subscription and billing details</p>
      </div>

      {/* Success/Error Alerts */}
      {successMessage && (
        <Alert className="border-green-200 bg-green-50">
          <Check className="h-4 w-4 text-green-600" />
          <AlertTitle className="text-green-800">Success!</AlertTitle>
          <AlertDescription className="text-green-700">{successMessage}</AlertDescription>
        </Alert>
      )}

      {error && (
        <Alert variant="destructive">
          <AlertCircle className="h-4 w-4" />
          <AlertTitle>Error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {/* Current Plan Status */}
      <Card>
        <CardHeader>
          <CardTitle>Current Plan</CardTitle>
          <CardDescription>Your active subscription details</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {currentPlan ? (
                <>
                  {getPlanIcon(currentPlan.slug)}
                  <div>
                    <p className="font-semibold text-lg">{currentPlan.name}</p>
                    <p className="text-sm text-gray-500">
                      ${currentPlan.price_monthly}/month
                    </p>
                  </div>
                </>
              ) : (
                <>
                  <CreditCard className="h-5 w-5 text-gray-400" />
                  <div>
                    <p className="font-semibold text-lg">Free Trial</p>
                    <p className="text-sm text-gray-500">
                      {trialDays > 0 ? `${trialDays} days remaining` : 'Trial expired'}
                    </p>
                  </div>
                </>
              )}
            </div>
            <Badge
              className={
                showroom?.subscription_status === 'active'
                  ? 'bg-green-100 text-green-800'
                  : showroom?.subscription_status === 'trial'
                  ? 'bg-yellow-100 text-yellow-800'
                  : showroom?.subscription_status === 'past_due'
                  ? 'bg-red-100 text-red-800'
                  : 'bg-gray-100 text-gray-800'
              }
            >
              {showroom?.subscription_status}
            </Badge>
          </div>

          {showroom?.cancel_at_period_end && (
            <Alert className="border-yellow-200 bg-yellow-50">
              <AlertTriangle className="h-4 w-4 text-yellow-600" />
              <AlertTitle className="text-yellow-800">Subscription Canceling</AlertTitle>
              <AlertDescription className="text-yellow-700">
                Your subscription will end on{' '}
                {showroom.current_period_end && formatDate(showroom.current_period_end)}.
                You can reactivate anytime before then.
              </AlertDescription>
            </Alert>
          )}

          {currentPlan && (
            <div className="grid grid-cols-3 gap-4 pt-4 border-t">
              <div>
                <p className="text-sm text-gray-500">Projects Used</p>
                <p className="text-lg font-semibold">
                  {showroom?.project_count_this_period || 0}
                  {currentPlan.project_limit && ` / ${currentPlan.project_limit}`}
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Storage</p>
                <p className="text-lg font-semibold">
                  {currentPlan.storage_limit_gb ? `${currentPlan.storage_limit_gb} GB` : 'Unlimited'}
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Team Members</p>
                <p className="text-lg font-semibold">
                  {currentPlan.team_member_limit || 'Unlimited'}
                </p>
              </div>
            </div>
          )}
        </CardContent>
        {showroom?.stripe_customer_id && (
          <CardFooter>
            <Button onClick={handleManageBilling} disabled={portalLoading} variant="outline">
              {portalLoading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Loading...
                </>
              ) : (
                <>
                  <ExternalLink className="mr-2 h-4 w-4" />
                  Manage Billing
                </>
              )}
            </Button>
          </CardFooter>
        )}
      </Card>

      {/* Pricing Plans */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold">Available Plans</h2>
          <div className="flex items-center gap-2 bg-gray-100 rounded-lg p-1">
            <button
              onClick={() => setBillingPeriod('monthly')}
              className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
                billingPeriod === 'monthly'
                  ? 'bg-white shadow text-gray-900'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Monthly
            </button>
            <button
              onClick={() => setBillingPeriod('yearly')}
              className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
                billingPeriod === 'yearly'
                  ? 'bg-white shadow text-gray-900'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Yearly (Save 17%)
            </button>
          </div>
        </div>

        <div className="grid md:grid-cols-3 gap-4">
          {plans
            .filter((p) => p.slug !== 'trial')
            .map((plan) => {
              const isCurrentPlan = showroom?.subscription_plan === plan.slug
              const price =
                billingPeriod === 'yearly' && plan.price_yearly
                  ? plan.price_yearly / 12
                  : plan.price_monthly

              return (
                <Card
                  key={plan.id}
                  className={`relative ${plan.is_featured ? 'border-blue-500 border-2' : ''}`}
                >
                  {plan.is_featured && (
                    <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                      <Badge className="bg-blue-500 text-white">Most Popular</Badge>
                    </div>
                  )}
                  <CardHeader>
                    <div className="flex items-center gap-2">
                      {getPlanIcon(plan.slug)}
                      <CardTitle>{plan.name}</CardTitle>
                    </div>
                    <CardDescription>{plan.description}</CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <div>
                      {plan.slug === 'enterprise' ? (
                        <p className="text-3xl font-bold">Custom</p>
                      ) : (
                        <>
                          <p className="text-3xl font-bold">
                            ${price.toFixed(0)}
                            <span className="text-base font-normal text-gray-500">/mo</span>
                          </p>
                          {billingPeriod === 'yearly' && (
                            <p className="text-sm text-gray-500">
                              Billed ${plan.price_yearly?.toFixed(0)}/year
                            </p>
                          )}
                        </>
                      )}
                    </div>

                    <Separator />

                    <ul className="space-y-2">
                      {(plan.features as string[]).map((feature, idx) => (
                        <li key={idx} className="flex items-center gap-2 text-sm">
                          <Check className="h-4 w-4 text-green-500 flex-shrink-0" />
                          {feature}
                        </li>
                      ))}
                    </ul>
                  </CardContent>
                  <CardFooter>
                    {plan.slug === 'enterprise' ? (
                      <Button className="w-full" variant="outline" asChild>
                        <a href="mailto:sales@nextlyn.ai">Contact Sales</a>
                      </Button>
                    ) : isCurrentPlan ? (
                      <Button className="w-full" disabled>
                        Current Plan
                      </Button>
                    ) : (
                      <Button
                        className="w-full"
                        onClick={() => handleSubscribe(plan.slug)}
                        disabled={checkoutLoading === plan.slug}
                      >
                        {checkoutLoading === plan.slug ? (
                          <>
                            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                            Loading...
                          </>
                        ) : showroom?.subscription_plan ? (
                          'Switch Plan'
                        ) : (
                          'Subscribe'
                        )}
                      </Button>
                    )}
                  </CardFooter>
                </Card>
              )
            })}
        </div>
      </div>

      {/* Invoice History */}
      {invoices.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Invoice History</CardTitle>
            <CardDescription>Your recent invoices and payments</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Invoice</TableHead>
                  <TableHead>Date</TableHead>
                  <TableHead>Amount</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {invoices.map((invoice) => (
                  <TableRow key={invoice.id}>
                    <TableCell className="font-medium">{invoice.invoice_number}</TableCell>
                    <TableCell>{formatDate(invoice.period_start)}</TableCell>
                    <TableCell>{formatPrice(invoice.total_cents, invoice.currency)}</TableCell>
                    <TableCell>
                      <Badge
                        className={
                          invoice.status === 'paid'
                            ? 'bg-green-100 text-green-800'
                            : invoice.status === 'open'
                            ? 'bg-yellow-100 text-yellow-800'
                            : 'bg-gray-100 text-gray-800'
                        }
                      >
                        {invoice.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      {invoice.invoice_pdf_url && (
                        <Button variant="ghost" size="sm" asChild>
                          <a
                            href={invoice.invoice_pdf_url}
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            <Download className="h-4 w-4" />
                          </a>
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Help Section */}
      <Card>
        <CardHeader>
          <CardTitle>Need Help?</CardTitle>
          <CardDescription>Questions about billing or subscriptions?</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-gray-600">
            If you have any questions about your subscription, billing, or need to make
            changes to your account, please contact our support team at{' '}
            <a href="mailto:support@nextlyn.ai" className="text-blue-600 hover:underline">
              support@nextlyn.ai
            </a>
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
