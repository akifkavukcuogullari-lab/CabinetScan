'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Clock, CreditCard, LogOut, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

export default function TrialExpiredPage() {
  const router = useRouter()
  const supabase = createClient()
  const [loading, setLoading] = useState(false)

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  const handleSubscribe = async () => {
    setLoading(true)
    try {
      // Get session and showroom info
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        toast.error('Please sign in again')
        router.push('/login')
        return
      }

      const { data: { user } } = await supabase.auth.getUser()
      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user?.id)
        .single()

      if (!showroomUser) {
        toast.error('Could not find your showroom')
        return
      }

      // Create Stripe checkout session for Pro plan (default recommendation)
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
            showroom_id: showroomUser.showroom_id,
            plan_slug: 'pro', // Default to Pro plan
            billing_period: 'monthly',
            success_url: `${window.location.origin}/showroom/projects?success=true`,
            cancel_url: `${window.location.origin}/trial-expired?canceled=true`,
          }),
        }
      )

      const data = await response.json()

      if (data.url) {
        window.location.href = data.url
      } else {
        toast.error(data.error || 'Failed to create checkout session')
      }
    } catch (error) {
      console.error('Subscribe error:', error)
      toast.error('Failed to start subscription process')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center space-y-4">
          <div className="mx-auto w-16 h-16 rounded-full bg-amber-100 flex items-center justify-center">
            <Clock className="h-8 w-8 text-amber-600" />
          </div>
          <div>
            <CardTitle className="text-2xl font-bold text-gray-700">Trial Expired</CardTitle>
            <CardDescription className="mt-2 text-base">
              Your free trial has ended
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="bg-amber-50 border border-amber-200 rounded-lg p-4">
            <p className="text-sm text-amber-800">
              Your 14-day free trial has expired. Subscribe to a plan to continue using CabinetScan and access all your data.
            </p>
          </div>

          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <div className="flex items-start gap-3">
              <CreditCard className="h-5 w-5 text-blue-600 mt-0.5" />
              <div>
                <p className="text-sm font-medium text-blue-800">Your data is safe</p>
                <p className="text-sm text-blue-700 mt-1">
                  All your projects and settings are preserved. Subscribe now to regain full access.
                </p>
              </div>
            </div>
          </div>
        </CardContent>
        <CardFooter className="flex flex-col space-y-3">
          <Button
            className="w-full gap-2"
            onClick={handleSubscribe}
            disabled={loading}
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Redirecting to checkout...
              </>
            ) : (
              <>
                <CreditCard className="h-4 w-4" />
                Subscribe Now
              </>
            )}
          </Button>
          <Button
            variant="outline"
            className="w-full gap-2"
            onClick={handleSignOut}
          >
            <LogOut className="h-4 w-4" />
            Sign Out
          </Button>
        </CardFooter>
      </Card>
    </div>
  )
}
