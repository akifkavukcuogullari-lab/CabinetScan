'use client'

import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { XCircle, Mail, LogOut, RefreshCw } from 'lucide-react'

export default function AccountCanceledPage() {
  const router = useRouter()
  const supabase = createClient()

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center space-y-4">
          <div className="mx-auto w-16 h-16 rounded-full bg-gray-100 flex items-center justify-center">
            <XCircle className="h-8 w-8 text-gray-600" />
          </div>
          <div>
            <CardTitle className="text-2xl font-bold text-gray-700">Subscription Canceled</CardTitle>
            <CardDescription className="mt-2 text-base">
              Your showroom subscription has ended
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
            <p className="text-sm text-gray-700">
              Your subscription has been canceled and access to the dashboard is no longer available.
            </p>
            <p className="mt-2 text-sm text-gray-600">
              If you believe this is an error or would like to reactivate your subscription, please contact our support team.
            </p>
          </div>

          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <div className="flex items-start gap-3">
              <RefreshCw className="h-5 w-5 text-blue-600 mt-0.5" />
              <div>
                <p className="text-sm font-medium text-blue-800">Want to come back?</p>
                <p className="text-sm text-blue-700 mt-1">
                  You can reactivate your subscription at any time. Your data is safely preserved.
                </p>
              </div>
            </div>
          </div>
        </CardContent>
        <CardFooter className="flex flex-col space-y-3">
          <Button
            className="w-full gap-2"
            onClick={() => window.location.href = 'mailto:support@nextlynscan.com?subject=Subscription%20Reactivation%20Request'}
          >
            <Mail className="h-4 w-4" />
            Contact Support to Reactivate
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
