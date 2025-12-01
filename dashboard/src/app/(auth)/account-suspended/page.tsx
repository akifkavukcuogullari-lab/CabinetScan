'use client'

import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { ShieldOff, Mail, LogOut } from 'lucide-react'

export default function AccountSuspendedPage() {
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
          <div className="mx-auto w-16 h-16 rounded-full bg-red-100 flex items-center justify-center">
            <ShieldOff className="h-8 w-8 text-red-600" />
          </div>
          <div>
            <CardTitle className="text-2xl font-bold text-red-600">Account Suspended</CardTitle>
            <CardDescription className="mt-2 text-base">
              Your showroom account has been suspended
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="bg-red-50 border border-red-200 rounded-lg p-4">
            <p className="text-sm text-red-800">
              Access to your dashboard has been temporarily blocked. This may be due to:
            </p>
            <ul className="mt-2 text-sm text-red-700 list-disc list-inside space-y-1">
              <li>Terms of service violation</li>
              <li>Suspicious activity detected</li>
              <li>Administrative action</li>
            </ul>
          </div>

          <div className="text-center space-y-2">
            <p className="text-sm text-gray-600">
              To resolve this issue and restore access to your account, please contact our support team.
            </p>
          </div>
        </CardContent>
        <CardFooter className="flex flex-col space-y-3">
          <Button
            className="w-full gap-2"
            onClick={() => window.location.href = 'mailto:support@nextlynscan.com?subject=Account%20Suspended%20-%20Request%20for%20Review'}
          >
            <Mail className="h-4 w-4" />
            Contact Support
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
