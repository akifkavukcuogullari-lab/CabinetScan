'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { formatError, logError, FormattedError } from '@/lib/errors'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Loader2, AlertCircle, Eye, EyeOff, Info } from 'lucide-react'

// Map common auth error messages to user-friendly versions
function formatAuthError(errorMessage: string): FormattedError {
  const message = errorMessage.toLowerCase()

  if (message.includes('invalid login credentials') || message.includes('invalid email or password')) {
    return {
      title: 'Invalid Credentials',
      message: 'The email or password you entered is incorrect.',
      suggestion: 'Please check your credentials and try again.',
      isRetryable: false,
    }
  }

  if (message.includes('email not confirmed')) {
    return {
      title: 'Email Not Verified',
      message: 'Please verify your email address before signing in.',
      suggestion: 'Check your inbox for the verification email.',
      isRetryable: false,
    }
  }

  if (message.includes('too many requests') || message.includes('rate limit')) {
    return {
      title: 'Too Many Attempts',
      message: 'You have made too many login attempts.',
      suggestion: 'Please wait a few minutes before trying again.',
      isRetryable: true,
    }
  }

  if (message.includes('user not found')) {
    return {
      title: 'Account Not Found',
      message: 'No account exists with this email address.',
      suggestion: 'Please check your email or contact support.',
      isRetryable: false,
    }
  }

  if (message.includes('network') || message.includes('fetch')) {
    return {
      title: 'Connection Error',
      message: 'Unable to connect to the server.',
      suggestion: 'Please check your internet connection and try again.',
      isRetryable: true,
    }
  }

  // Default fallback
  return {
    title: 'Sign In Failed',
    message: errorMessage,
    isRetryable: false,
  }
}

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<FormattedError | null>(null)
  const [loading, setLoading] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    try {
      const { error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      })

      if (authError) {
        const formatted = formatAuthError(authError.message)
        logError(authError, { context: 'login', email })
        setError(formatted)
        toast.error(formatted.title, {
          description: formatted.message,
        })
        setLoading(false)
        return
      }

      // Check if user is admin or showroom owner
      const { data: admin, error: adminError } = await supabase
        .from('admins')
        .select('id')
        .single()

      if (adminError && adminError.code !== 'PGRST116') {
        // PGRST116 = no rows returned, which is expected for non-admins
        logError(adminError, { context: 'checkAdminRole', email })
      }

      if (admin) {
        toast.success('Welcome back!', {
          description: 'Redirecting to admin dashboard...',
        })
        router.push('/admin/showrooms')
        return
      }

      // Get current user's auth info for the filter
      const { data: { user: authUser } } = await supabase.auth.getUser()

      const { data: showroomUser, error: showroomError } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', authUser?.id)
        .eq('is_active', true)
        .single()

      if (showroomError && showroomError.code !== 'PGRST116') {
        logError(showroomError, { context: 'checkShowroomRole', email })
      }

      if (showroomUser) {
        // Check showroom subscription status
        const { data: showroom, error: showroomStatusError } = await supabase
          .from('showrooms')
          .select('subscription_status, trial_ends_at, name')
          .eq('id', showroomUser.showroom_id)
          .single()

        if (showroomStatusError) {
          logError(showroomStatusError, { context: 'checkShowroomStatus', email })
        }

        // Check if trial has expired
        const isTrialExpired = showroom?.subscription_status === 'trial' &&
          showroom?.trial_ends_at &&
          new Date(showroom.trial_ends_at) < new Date()

        if (isTrialExpired) {
          const trialExpiredError: FormattedError = {
            title: 'Trial Expired',
            message: 'Your free trial has ended.',
            suggestion: 'Please subscribe to a plan to continue using CabinetScan.',
            isRetryable: false,
          }
          setError(trialExpiredError)
          toast.error(trialExpiredError.title, {
            description: trialExpiredError.message,
          })
          await supabase.auth.signOut()
          setLoading(false)
          return
        }

        // Block access for suspended or canceled subscriptions
        if (showroom?.subscription_status === 'suspended') {
          const suspendedError: FormattedError = {
            title: 'Account Suspended',
            message: 'Your showroom account has been suspended.',
            suggestion: 'Please contact support to resolve this issue and restore access.',
            isRetryable: false,
          }
          setError(suspendedError)
          toast.error(suspendedError.title, {
            description: suspendedError.message,
          })
          await supabase.auth.signOut()
          setLoading(false)
          return
        }

        if (showroom?.subscription_status === 'canceled') {
          const canceledError: FormattedError = {
            title: 'Subscription Canceled',
            message: 'Your showroom subscription has been canceled.',
            suggestion: 'Please contact support to reactivate your account.',
            isRetryable: false,
          }
          setError(canceledError)
          toast.error(canceledError.title, {
            description: canceledError.message,
          })
          await supabase.auth.signOut()
          setLoading(false)
          return
        }

        toast.success('Welcome back!', {
          description: 'Redirecting to your dashboard...',
        })
        router.push('/showroom/projects')
        return
      }

      // No access configured
      const noAccessError: FormattedError = {
        title: 'Access Denied',
        message: 'No dashboard access has been configured for this account.',
        suggestion: 'Please contact your administrator to request access.',
        isRetryable: false,
      }
      setError(noAccessError)
      toast.error(noAccessError.title, {
        description: noAccessError.message,
      })
      await supabase.auth.signOut()
    } catch (err) {
      logError(err, { context: 'handleLogin', email })
      const formatted = formatError(err)
      setError(formatted)
      toast.error(formatted.title, {
        description: formatted.message,
      })
    } finally {
      setLoading(false)
    }
  }

  const handleInputChange = () => {
    // Clear error when user starts typing
    if (error) setError(null)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold">Sign in</CardTitle>
          <CardDescription>
            Enter your email and password to access the dashboard
          </CardDescription>
        </CardHeader>
        <form onSubmit={handleLogin} aria-label="Sign in form">
          <CardContent className="space-y-4">
            {error && (
              <div
                className="p-4 rounded-lg bg-red-50 border border-red-200"
                role="alert"
                aria-live="assertive"
              >
                <div className="flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-red-600 mt-0.5 flex-shrink-0" aria-hidden="true" />
                  <div className="flex-1">
                    <p className="font-medium text-red-800">{error.title}</p>
                    <p className="text-sm text-red-700 mt-1">{error.message}</p>
                    {error.suggestion && (
                      <p className="text-sm text-red-600 mt-2">{error.suggestion}</p>
                    )}
                  </div>
                </div>
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="name@company.com"
                value={email}
                onChange={(e) => {
                  setEmail(e.target.value)
                  handleInputChange()
                }}
                required
                disabled={loading}
                aria-required="true"
                autoComplete="email"
              />
            </div>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="password">Password</Label>
                <Link
                  href="/forgot-password"
                  className="text-sm text-blue-600 hover:underline"
                >
                  Forgot password?
                </Link>
              </div>
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => {
                    setPassword(e.target.value)
                    handleInputChange()
                  }}
                  required
                  disabled={loading}
                  aria-required="true"
                  autoComplete="current-password"
                  className="pr-10"
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="absolute right-0 top-0 h-full px-3 py-2 hover:bg-transparent"
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  disabled={loading}
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4 text-gray-400" aria-hidden="true" />
                  ) : (
                    <Eye className="h-4 w-4 text-gray-400" aria-hidden="true" />
                  )}
                </Button>
              </div>
            </div>
          </CardContent>
          <CardFooter className="flex flex-col space-y-4">
            <Button
              type="submit"
              className="w-full"
              disabled={loading}
              aria-label={loading ? 'Signing in...' : 'Sign in'}
            >
              {loading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />
                  Signing in...
                </>
              ) : (
                'Sign in'
              )}
            </Button>
            <p className="text-sm text-gray-600 text-center">
              Don&apos;t have an account?{' '}
              <Link href="/register" className="text-blue-600 hover:underline">
                Contact support
              </Link>
            </p>
            <Link
              href="/intro"
              className="inline-flex items-center justify-center gap-2 text-sm text-purple-600 hover:text-purple-700 transition-colors"
            >
              <Info className="h-4 w-4" />
              Learn more about CabinetScan
            </Link>
          </CardFooter>
        </form>
      </Card>
    </div>
  )
}
