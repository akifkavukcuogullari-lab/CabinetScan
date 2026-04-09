'use client'

import { useState, useEffect, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { CheckCircle2, XCircle, Loader2, Eye, EyeOff } from 'lucide-react'

interface DesignerInvitation {
  id: string
  email: string
  full_name: string
  expires_at: string
  accepted_at: string | null
}

function AcceptDesignerInvitationContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const token = searchParams.get('token')

  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [invitation, setInvitation] = useState<DesignerInvitation | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [showPassword, setShowPassword] = useState(false)

  const [formData, setFormData] = useState({
    password: '',
    confirmPassword: '',
  })

  const [formErrors, setFormErrors] = useState<{
    password?: string
    confirmPassword?: string
  }>({})

  // Validate token on mount
  useEffect(() => {
    async function validateToken() {
      if (!token) {
        setError('No invitation token provided')
        setLoading(false)
        return
      }

      try {
        const supabase = createClient()

        // Query designer_invitations directly using the token
        const { data, error: queryError } = await supabase
          .from('designer_invitations')
          .select('id, email, full_name, expires_at, accepted_at')
          .eq('token', token)
          .single()

        if (queryError || !data) {
          setError('Invitation not found. It may have been revoked or the link is incorrect.')
          setLoading(false)
          return
        }

        // Check if already accepted
        if (data.accepted_at) {
          setError('This invitation has already been accepted. Please sign in instead.')
          setLoading(false)
          return
        }

        // Check if expired
        if (new Date(data.expires_at) < new Date()) {
          setError('This invitation has expired. Please contact the administrator for a new invitation.')
          setLoading(false)
          return
        }

        setInvitation(data)
      } catch (err) {
        console.error('Failed to validate invitation:', err)
        setError('Failed to validate invitation. Please try again.')
      } finally {
        setLoading(false)
      }
    }

    validateToken()
  }, [token])

  const validateForm = (): boolean => {
    const errors: typeof formErrors = {}

    if (!formData.password) {
      errors.password = 'Password is required'
    } else if (formData.password.length < 8) {
      errors.password = 'Password must be at least 8 characters'
    }

    if (formData.password !== formData.confirmPassword) {
      errors.confirmPassword = 'Passwords do not match'
    }

    setFormErrors(errors)
    return Object.keys(errors).length === 0
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!validateForm() || !token || !invitation) return

    setSubmitting(true)
    setError(null)

    try {
      const supabase = createClient()

      // Step 1: Create auth user with email + password
      const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
        email: invitation.email,
        password: formData.password,
        options: {
          data: {
            full_name: invitation.full_name,
            role: 'designer',
          },
        },
      })

      if (signUpError) {
        // If user already exists, show appropriate message
        if (signUpError.message.includes('already registered')) {
          setError('An account with this email already exists. Please sign in instead.')
        } else {
          setError(signUpError.message)
        }
        return
      }

      if (!signUpData.user) {
        setError('Failed to create account. Please try again.')
        return
      }

      const userId = signUpData.user.id

      // Step 2: Insert row in designers table
      const { error: designerError } = await supabase
        .from('designers')
        .insert({
          user_id: userId,
          email: invitation.email,
          full_name: invitation.full_name,
          is_active: true,
        })

      if (designerError) {
        console.error('Failed to create designer record:', designerError)
        // Don't block - the admin can fix this later if needed
      }

      // Step 3: Update designer_invitations to set accepted_at
      const { error: updateError } = await supabase
        .from('designer_invitations')
        .update({ accepted_at: new Date().toISOString() })
        .eq('id', invitation.id)

      if (updateError) {
        console.error('Failed to update invitation:', updateError)
        // Don't block - the account was created successfully
      }

      // Sign out since the user needs to confirm email or sign in fresh
      await supabase.auth.signOut()

      setSuccess(true)

      // Redirect to login after a short delay
      setTimeout(() => {
        router.push('/login?message=Account created successfully. Please sign in.')
      }, 2000)
    } catch (err) {
      console.error('Failed to accept invitation:', err)
      setError('An error occurred. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target
    setFormData((prev) => ({ ...prev, [name]: value }))

    // Clear field-specific error when user types
    if (formErrors[name as keyof typeof formErrors]) {
      setFormErrors((prev) => ({ ...prev, [name]: undefined }))
    }
  }

  // Loading state
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <Card className="w-full max-w-md">
          <CardContent className="flex flex-col items-center py-12">
            <Loader2 className="h-8 w-8 animate-spin text-blue-600 mb-4" />
            <p className="text-gray-600">Validating invitation...</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Error state (invalid/expired invitation)
  if (error && !invitation) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <Card className="w-full max-w-md">
          <CardContent className="flex flex-col items-center py-12">
            <XCircle className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-semibold text-gray-900 mb-2">
              Invitation Invalid
            </h2>
            <p className="text-gray-600 text-center mb-6">{error}</p>
            <div className="flex gap-4">
              <Link href="/login">
                <Button variant="outline">Sign In</Button>
              </Link>
              <Link href="mailto:support@nextlyn.ai">
                <Button>Contact Support</Button>
              </Link>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Success state
  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <Card className="w-full max-w-md">
          <CardContent className="flex flex-col items-center py-12">
            <div className="h-16 w-16 bg-green-100 rounded-full flex items-center justify-center mb-4">
              <CheckCircle2 className="h-10 w-10 text-green-600" />
            </div>
            <h2 className="text-xl font-semibold text-gray-900 mb-2">
              Account Created!
            </h2>
            <p className="text-gray-600 text-center mb-2">
              Welcome to CabinetScan, {invitation?.full_name}
            </p>
            <p className="text-sm text-gray-500 text-center">
              Redirecting you to sign in...
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Invitation form
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4 py-12">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold">
            Welcome, {invitation?.full_name}
          </CardTitle>
          <CardDescription>
            Set up your designer account on CabinetScan
          </CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit}>
          <CardContent className="space-y-4">
            {error && (
              <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md">
                {error}
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={invitation?.email || ''}
                disabled
                className="bg-gray-50"
              />
              <p className="text-xs text-gray-500">
                This is the email address your invitation was sent to
              </p>
            </div>

            <div className="space-y-2">
              <Label htmlFor="fullName">Full Name</Label>
              <Input
                id="fullName"
                type="text"
                value={invitation?.full_name || ''}
                disabled
                className="bg-gray-50"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <div className="relative">
                <Input
                  id="password"
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  placeholder="At least 8 characters"
                  value={formData.password}
                  onChange={handleChange}
                  className={formErrors.password ? 'border-red-500 pr-10' : 'pr-10'}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700"
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
              {formErrors.password && (
                <p className="text-xs text-red-500">{formErrors.password}</p>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="confirmPassword">Confirm Password</Label>
              <Input
                id="confirmPassword"
                name="confirmPassword"
                type={showPassword ? 'text' : 'password'}
                placeholder="Confirm your password"
                value={formData.confirmPassword}
                onChange={handleChange}
                className={formErrors.confirmPassword ? 'border-red-500' : ''}
              />
              {formErrors.confirmPassword && (
                <p className="text-xs text-red-500">
                  {formErrors.confirmPassword}
                </p>
              )}
            </div>

            <Button
              type="submit"
              className="w-full"
              disabled={submitting}
            >
              {submitting ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Creating Account...
                </>
              ) : (
                'Create Account'
              )}
            </Button>

            <p className="text-xs text-gray-500 text-center">
              By creating an account, you agree to our{' '}
              <Link href="/terms" className="text-blue-600 hover:underline">
                Terms of Service
              </Link>{' '}
              and{' '}
              <Link href="/privacy" className="text-blue-600 hover:underline">
                Privacy Policy
              </Link>
            </p>
          </CardContent>
        </form>
      </Card>
    </div>
  )
}

// Wrap with Suspense for useSearchParams
export default function AcceptDesignerInvitationPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
          <Card className="w-full max-w-md">
            <CardContent className="flex flex-col items-center py-12">
              <Loader2 className="h-8 w-8 animate-spin text-blue-600 mb-4" />
              <p className="text-gray-600">Loading...</p>
            </CardContent>
          </Card>
        </div>
      }
    >
      <AcceptDesignerInvitationContent />
    </Suspense>
  )
}
