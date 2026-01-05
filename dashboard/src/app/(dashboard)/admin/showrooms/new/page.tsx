'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import {
  formatError,
  logError,
  isUniqueViolation,
  isPermissionError,
  createContextualErrorFormatter,
  FormattedError,
} from '@/lib/errors'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  ArrowLeft,
  Loader2,
  Mail,
  AlertCircle,
  HelpCircle,
  RefreshCw,
} from 'lucide-react'

function generateShowroomCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let result = ''
  for (let i = 0; i < 6; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return result
}

function generateSlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
}

// Create a contextual error formatter for showroom-specific fields
const formatShowroomError = createContextualErrorFormatter({
  showroom_code: 'showroom code',
  slug: 'showroom URL',
  email: 'email address',
  name: 'showroom name',
})

interface InvitationResult {
  sent: boolean
  error?: string
}

export default function NewShowroomPage() {
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<FormattedError | null>(null)
  const [invitationResult, setInvitationResult] = useState<InvitationResult | null>(null)
  const [createdShowroomId, setCreatedShowroomId] = useState<string | null>(null)

  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    addressLine1: '',
    addressLine2: '',
    city: '',
    state: '',
    postalCode: '',
    ownerName: '',
    ownerEmail: '',
    sendInvitation: true,
  })

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData((prev) => ({
      ...prev,
      [e.target.name]: e.target.value,
    }))
    // Clear error when user starts typing
    if (error) setError(null)
  }

  const handleSwitchChange = (checked: boolean) => {
    setFormData((prev) => ({
      ...prev,
      sendInvitation: checked,
    }))
  }

  const sendInvitation = async (
    showroomId: string,
    ownerEmail: string,
    ownerName: string
  ): Promise<InvitationResult> => {
    try {
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        return { sent: false, error: 'Your session has expired. Please sign in again.' }
      }

      // Add timeout to prevent hanging forever
      const controller = new AbortController()
      const timeoutId = setTimeout(() => controller.abort(), 30000) // 30 second timeout

      try {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-invitation`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${session.access_token}`,
              'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
            },
            body: JSON.stringify({
              showroom_id: showroomId,
              email: ownerEmail,
              full_name: ownerName || undefined,
            }),
            signal: controller.signal,
          }
        )

        clearTimeout(timeoutId)

        const data = await response.json()

        if (!response.ok || !data.success) {
          const errorMessage = data.error || 'Failed to send invitation email'
          return { sent: false, error: errorMessage }
        }

        // Check for warning (success but with error - email might have failed)
        if (data.error) {
          return { sent: true, error: data.error }
        }

        return { sent: true }
      } catch (fetchErr) {
        clearTimeout(timeoutId)
        if (fetchErr instanceof Error && fetchErr.name === 'AbortError') {
          return { sent: false, error: 'Request timed out. Please try again.' }
        }
        throw fetchErr
      }
    } catch (err) {
      logError(err, { context: 'sendInvitation', showroomId, ownerEmail })
      const formatted = formatError(err)
      return { sent: false, error: formatted.message }
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    setInvitationResult(null)

    // Show loading toast
    const loadingToast = toast.loading('Creating showroom...', {
      description: 'Validating information...',
    })

    try {
      // Check if showroom email already exists
      const { data: existingShowroom } = await supabase
        .from('showrooms')
        .select('id, name')
        .eq('email', formData.email)
        .single()

      if (existingShowroom) {
        toast.dismiss(loadingToast)
        const formatted: FormattedError = {
          title: 'Email Already Exists',
          message: `A showroom with email "${formData.email}" already exists (${existingShowroom.name}). Please use a different email address.`,
          suggestion: 'Each showroom must have a unique email address.',
          isRetryable: false,
        }
        setError(formatted)
        toast.error(formatted.title, { description: formatted.message })
        setLoading(false)
        return
      }

      // Check if owner email already exists in showroom_users
      if (formData.ownerEmail) {
        const { data: existingUser } = await supabase
          .from('showroom_users')
          .select('id, showroom_id')
          .eq('email', formData.ownerEmail)
          .single()

        if (existingUser) {
          toast.dismiss(loadingToast)
          const formatted: FormattedError = {
            title: 'Owner Email Already Exists',
            message: `The email "${formData.ownerEmail}" is already associated with another showroom. Each user can only belong to one showroom.`,
            suggestion: 'Please use a different email address for the owner.',
            isRetryable: false,
          }
          setError(formatted)
          toast.error(formatted.title, { description: formatted.message })
          setLoading(false)
          return
        }
      }

      toast.loading('Creating showroom...', {
        id: loadingToast,
        description: 'Setting up your new showroom configuration',
      })

      const showroomCode = generateShowroomCode()
      const slug = generateSlug(formData.name)

      // Create the showroom
      const { data: showroom, error: showroomError } = await supabase
        .from('showrooms')
        .insert({
          name: formData.name,
          slug,
          showroom_code: showroomCode,
          email: formData.email,
          phone: formData.phone || null,
          address_line1: formData.addressLine1 || null,
          address_line2: formData.addressLine2 || null,
          city: formData.city || null,
          state: formData.state || null,
          postal_code: formData.postalCode || null,
          subscription_status: 'trial',
          subscription_plan: 'pro',
          trial_ends_at: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(),
        })
        .select()
        .single()

      if (showroomError) {
        // Dismiss loading toast
        toast.dismiss(loadingToast)

        // Format the error with context
        const formatted = formatShowroomError(showroomError)
        logError(showroomError, { context: 'createShowroom', formData: { name: formData.name, email: formData.email } })

        // Show specific error toasts based on error type
        if (isPermissionError(showroomError)) {
          toast.error('Permission Denied', {
            description: 'You do not have permission to create showrooms. Please contact your administrator.',
            action: {
              label: 'Contact Support',
              onClick: () => window.location.href = 'mailto:support@nextleanscan.com',
            },
          })
        } else if (isUniqueViolation(showroomError)) {
          toast.error('Duplicate Entry', {
            description: formatted.message,
          })
        } else {
          toast.error(formatted.title, {
            description: formatted.message,
          })
        }

        setError(formatted)
        setLoading(false)
        return
      }

      setCreatedShowroomId(showroom.id)

      // Update loading toast
      toast.loading('Creating showroom...', {
        id: loadingToast,
        description: 'Setting up branding and categories',
      })

      // Create default branding
      const { error: brandingError } = await supabase.from('showroom_branding').insert({
        showroom_id: showroom.id,
      })

      if (brandingError) {
        logError(brandingError, { context: 'createShowroomBranding', showroomId: showroom.id })
        // Non-critical error, continue but warn
        toast.warning('Branding Setup', {
          description: 'Default branding could not be created. You can set it up later in settings.',
        })
      }

      // Enable all categories by default
      const { data: categories, error: categoriesError } = await supabase
        .from('categories')
        .select('id, display_order')
        .eq('is_active', true)

      if (categoriesError) {
        logError(categoriesError, { context: 'fetchCategories', showroomId: showroom.id })
      }

      if (categories && categories.length > 0) {
        const { error: categoryLinkError } = await supabase.from('showroom_categories').insert(
          categories.map((cat: { id: string; display_order: number }) => ({
            showroom_id: showroom.id,
            category_id: cat.id,
            is_enabled: true,
            display_order: cat.display_order,
          }))
        )

        if (categoryLinkError) {
          logError(categoryLinkError, { context: 'createShowroomCategories', showroomId: showroom.id })
        }
      }

      // Dismiss loading toast
      toast.dismiss(loadingToast)

      // Send invitation if owner email is provided and option is checked
      if (formData.ownerEmail && formData.sendInvitation) {
        const invitationToast = toast.loading('Sending invitation...', {
          description: `Sending invitation to ${formData.ownerEmail}`,
        })

        const result = await sendInvitation(
          showroom.id,
          formData.ownerEmail,
          formData.ownerName
        )
        setInvitationResult(result)

        // Always dismiss the invitation loading toast
        toast.dismiss(invitationToast)

        if (!result.sent) {
          // Show warning but don't block - showroom is created
          toast.warning('Invitation Not Sent', {
            description: result.error || 'The invitation could not be sent. You can retry from the showroom page.',
          })
          setLoading(false)
          // Don't navigate away, let user see the result and retry
          return
        }

        // Check if there's a warning (invitation created but email may have failed)
        if (result.error) {
          toast.warning('Showroom Created', {
            description: result.error,
          })
        } else {
          // Full success - show success toast
          toast.success('Showroom Created', {
            description: `${formData.name} has been created and invitation sent to ${formData.ownerEmail}`,
          })
        }
      } else {
        // Success without invitation
        toast.success('Showroom Created', {
          description: `${formData.name} has been created successfully.`,
        })
      }

      // Navigate to the showroom detail page
      router.push(`/admin/showrooms/${showroom.id}`)
    } catch (err) {
      toast.dismiss(loadingToast)
      logError(err, { context: 'handleSubmit', formData: { name: formData.name, email: formData.email } })

      const formatted = formatError(err)
      setError(formatted)

      toast.error(formatted.title, {
        description: formatted.message,
        action: formatted.isRetryable
          ? { label: 'Retry', onClick: () => handleSubmit(e) }
          : undefined,
      })

      setLoading(false)
    }
  }

  const handleRetryInvitation = async () => {
    if (!createdShowroomId || !formData.ownerEmail) return

    setLoading(true)
    const loadingToast = toast.loading('Retrying invitation...', {
      description: `Sending to ${formData.ownerEmail}`,
    })

    const result = await sendInvitation(
      createdShowroomId,
      formData.ownerEmail,
      formData.ownerName
    )
    setInvitationResult(result)
    setLoading(false)
    toast.dismiss(loadingToast)

    if (result.sent) {
      toast.success('Invitation Sent', {
        description: `Invitation successfully sent to ${formData.ownerEmail}`,
      })
      router.push(`/admin/showrooms/${createdShowroomId}`)
    } else {
      toast.error('Invitation Failed', {
        description: result.error || 'Unable to send invitation. Please try again.',
      })
    }
  }

  const handleSkipInvitation = () => {
    if (createdShowroomId) {
      toast.info('Invitation Skipped', {
        description: 'You can send the invitation later from the showroom settings.',
      })
      router.push(`/admin/showrooms/${createdShowroomId}`)
    }
  }

  // Show invitation result screen if showroom created but invitation pending
  if (createdShowroomId && invitationResult && !invitationResult.sent) {
    return (
      <div className="max-w-2xl mx-auto space-y-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AlertCircle className="h-5 w-5 text-yellow-500" aria-hidden="true" />
              Showroom Created - Invitation Issue
            </CardTitle>
            <CardDescription>
              The showroom was created successfully, but we couldn&apos;t send the invitation email.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div
              className="p-4 bg-yellow-50 border border-yellow-200 rounded-lg"
              role="alert"
              aria-live="polite"
            >
              <p className="text-sm text-yellow-800">
                <strong>Issue:</strong> {invitationResult.error}
              </p>
            </div>

            <div className="p-4 bg-gray-50 rounded-lg">
              <p className="text-sm text-gray-600 mb-1">Invitation will be sent to:</p>
              <p className="font-medium">{formData.ownerEmail}</p>
              {formData.ownerName && (
                <p className="text-sm text-gray-500">{formData.ownerName}</p>
              )}
            </div>

            <div className="flex gap-4">
              <Button
                onClick={handleRetryInvitation}
                disabled={loading}
                aria-label="Retry sending invitation"
              >
                {loading ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />
                    Retrying...
                  </>
                ) : (
                  <>
                    <RefreshCw className="mr-2 h-4 w-4" aria-hidden="true" />
                    Retry Invitation
                  </>
                )}
              </Button>
              <Button
                variant="outline"
                onClick={handleSkipInvitation}
                disabled={loading}
              >
                Skip for Now
              </Button>
            </div>

            <p className="text-xs text-gray-500 flex items-center gap-1">
              <HelpCircle className="h-3 w-3" aria-hidden="true" />
              You can also send the invitation later from the showroom management page.
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Link href="/admin/showrooms">
          <Button
            variant="ghost"
            size="icon"
            aria-label="Go back to showrooms list"
          >
            <ArrowLeft className="h-5 w-5" aria-hidden="true" />
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold">Create Showroom</h1>
          <p className="text-gray-500">Add a new showroom tenant</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} aria-label="Create showroom form">
        <Card>
          <CardHeader>
            <CardTitle>Showroom Details</CardTitle>
            <CardDescription>Basic information about the showroom</CardDescription>
          </CardHeader>
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
                    {error.isRetryable && (
                      <Button
                        variant="outline"
                        size="sm"
                        className="mt-3 text-red-700 border-red-300 hover:bg-red-100"
                        onClick={(e) => {
                          e.preventDefault()
                          setError(null)
                        }}
                      >
                        <RefreshCw className="h-3 w-3 mr-2" aria-hidden="true" />
                        Dismiss and Retry
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="name">
                Showroom Name <span className="text-red-500">*</span>
              </Label>
              <Input
                id="name"
                name="name"
                value={formData.name}
                onChange={handleChange}
                placeholder="ABC Cabinets"
                required
                aria-required="true"
                disabled={loading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">
                Business Email <span className="text-red-500">*</span>
              </Label>
              <Input
                id="email"
                name="email"
                type="email"
                value={formData.email}
                onChange={handleChange}
                placeholder="info@abccabinets.com"
                required
                aria-required="true"
                disabled={loading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="phone">Phone</Label>
              <Input
                id="phone"
                name="phone"
                type="tel"
                value={formData.phone}
                onChange={handleChange}
                placeholder="(555) 123-4567"
                disabled={loading}
              />
            </div>
          </CardContent>
        </Card>

        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Address</CardTitle>
            <CardDescription>Showroom physical location</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="addressLine1">Address Line 1</Label>
              <Input
                id="addressLine1"
                name="addressLine1"
                value={formData.addressLine1}
                onChange={handleChange}
                placeholder="123 Main Street"
                disabled={loading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="addressLine2">Address Line 2</Label>
              <Input
                id="addressLine2"
                name="addressLine2"
                value={formData.addressLine2}
                onChange={handleChange}
                placeholder="Suite 100"
                disabled={loading}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="city">City</Label>
                <Input
                  id="city"
                  name="city"
                  value={formData.city}
                  onChange={handleChange}
                  placeholder="New York"
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="state">State</Label>
                <Input
                  id="state"
                  name="state"
                  value={formData.state}
                  onChange={handleChange}
                  placeholder="NY"
                  disabled={loading}
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="postalCode">Postal Code</Label>
              <Input
                id="postalCode"
                name="postalCode"
                value={formData.postalCode}
                onChange={handleChange}
                placeholder="10001"
                disabled={loading}
              />
            </div>
          </CardContent>
        </Card>

        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Primary Owner</CardTitle>
            <CardDescription>
              The main account holder who will manage this showroom
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="ownerName">Owner Name</Label>
              <Input
                id="ownerName"
                name="ownerName"
                value={formData.ownerName}
                onChange={handleChange}
                placeholder="John Smith"
                disabled={loading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="ownerEmail">
                Owner Email <span className="text-red-500">*</span>
              </Label>
              <Input
                id="ownerEmail"
                name="ownerEmail"
                type="email"
                value={formData.ownerEmail}
                onChange={handleChange}
                placeholder="john@abccabinets.com"
                required
                aria-required="true"
                disabled={loading}
              />
            </div>

            <div className="flex items-center justify-between pt-2">
              <div className="space-y-0.5">
                <Label htmlFor="sendInvitation" className="text-base">
                  Send invitation email
                </Label>
                <p className="text-sm text-gray-500">
                  An email with a signup link will be sent to the owner
                </p>
              </div>
              <Switch
                id="sendInvitation"
                checked={formData.sendInvitation}
                onCheckedChange={handleSwitchChange}
                disabled={loading}
                aria-label="Toggle invitation email"
              />
            </div>

            {!formData.sendInvitation && formData.ownerEmail && (
              <div
                className="p-3 text-sm text-yellow-800 bg-yellow-50 rounded-md border border-yellow-200"
                role="status"
              >
                <strong>Note:</strong> The owner won&apos;t receive an invitation email.
                You&apos;ll need to send it manually later from the showroom settings.
              </div>
            )}
          </CardContent>
        </Card>

        <div className="flex justify-end gap-4 mt-6">
          <Link href="/admin/showrooms">
            <Button variant="outline" type="button" disabled={loading}>
              Cancel
            </Button>
          </Link>
          <Button
            type="submit"
            disabled={loading}
            aria-label={loading ? 'Creating showroom...' : 'Create showroom'}
          >
            {loading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />
                Creating...
              </>
            ) : (
              'Create Showroom'
            )}
          </Button>
        </div>
      </form>
    </div>
  )
}
