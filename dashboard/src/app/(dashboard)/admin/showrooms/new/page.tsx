'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
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
import { ArrowLeft, Loader2, Mail, CheckCircle2, AlertCircle } from 'lucide-react'

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

interface InvitationResult {
  sent: boolean
  error?: string
}

export default function NewShowroomPage() {
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
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
        return { sent: false, error: 'Not authenticated' }
      }

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
        }
      )

      const data = await response.json()

      if (!response.ok || !data.success) {
        return { sent: false, error: data.error || 'Failed to send invitation' }
      }

      return { sent: true }
    } catch (err) {
      console.error('Failed to send invitation:', err)
      return { sent: false, error: 'Failed to send invitation' }
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    setInvitationResult(null)

    try {
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
          trial_ends_at: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(),
        })
        .select()
        .single()

      if (showroomError) throw showroomError

      setCreatedShowroomId(showroom.id)

      // Create default branding
      await supabase.from('showroom_branding').insert({
        showroom_id: showroom.id,
      })

      // Enable all categories by default
      const { data: categories } = await supabase
        .from('categories')
        .select('id, display_order')
        .eq('is_active', true)

      if (categories && categories.length > 0) {
        await supabase.from('showroom_categories').insert(
          categories.map((cat: { id: string; display_order: number }) => ({
            showroom_id: showroom.id,
            category_id: cat.id,
            is_enabled: true,
            display_order: cat.display_order,
          }))
        )
      }

      // Send invitation if owner email is provided and option is checked
      if (formData.ownerEmail && formData.sendInvitation) {
        const result = await sendInvitation(
          showroom.id,
          formData.ownerEmail,
          formData.ownerName
        )
        setInvitationResult(result)

        // Even if invitation fails, showroom is created - just show warning
        if (!result.sent) {
          setLoading(false)
          // Don't navigate away, let user see the result and retry
          return
        }
      }

      // Navigate to the showroom detail page
      router.push(`/admin/showrooms/${showroom.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create showroom')
      setLoading(false)
    }
  }

  const handleRetryInvitation = async () => {
    if (!createdShowroomId || !formData.ownerEmail) return

    setLoading(true)
    const result = await sendInvitation(
      createdShowroomId,
      formData.ownerEmail,
      formData.ownerName
    )
    setInvitationResult(result)
    setLoading(false)

    if (result.sent) {
      router.push(`/admin/showrooms/${createdShowroomId}`)
    }
  }

  const handleSkipInvitation = () => {
    if (createdShowroomId) {
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
              <AlertCircle className="h-5 w-5 text-yellow-500" />
              Showroom Created - Invitation Issue
            </CardTitle>
            <CardDescription>
              The showroom was created successfully, but we couldn&apos;t send the invitation email.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
              <p className="text-sm text-yellow-800">
                <strong>Error:</strong> {invitationResult.error}
              </p>
            </div>

            <div className="p-4 bg-gray-50 rounded-lg">
              <p className="text-sm text-gray-600 mb-1">Invitation would be sent to:</p>
              <p className="font-medium">{formData.ownerEmail}</p>
            </div>

            <div className="flex gap-4">
              <Button onClick={handleRetryInvitation} disabled={loading}>
                {loading ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Retrying...
                  </>
                ) : (
                  <>
                    <Mail className="mr-2 h-4 w-4" />
                    Retry Invitation
                  </>
                )}
              </Button>
              <Button variant="outline" onClick={handleSkipInvitation}>
                Skip for Now
              </Button>
            </div>

            <p className="text-xs text-gray-500">
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
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold">Create Showroom</h1>
          <p className="text-gray-500">Add a new showroom tenant</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Showroom Details</CardTitle>
            <CardDescription>Basic information about the showroom</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {error && (
              <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md">
                {error}
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="name">Showroom Name *</Label>
              <Input
                id="name"
                name="name"
                value={formData.name}
                onChange={handleChange}
                placeholder="ABC Cabinets"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">Business Email *</Label>
              <Input
                id="email"
                name="email"
                type="email"
                value={formData.email}
                onChange={handleChange}
                placeholder="info@abccabinets.com"
                required
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
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="ownerEmail">Owner Email *</Label>
              <Input
                id="ownerEmail"
                name="ownerEmail"
                type="email"
                value={formData.ownerEmail}
                onChange={handleChange}
                placeholder="john@abccabinets.com"
                required
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
              />
            </div>

            {!formData.sendInvitation && formData.ownerEmail && (
              <div className="p-3 text-sm text-yellow-800 bg-yellow-50 rounded-md border border-yellow-200">
                <strong>Note:</strong> The owner won&apos;t receive an invitation email.
                You&apos;ll need to send it manually later from the showroom settings.
              </div>
            )}
          </CardContent>
        </Card>

        <div className="flex justify-end gap-4 mt-6">
          <Link href="/admin/showrooms">
            <Button variant="outline" type="button">
              Cancel
            </Button>
          </Link>
          <Button type="submit" disabled={loading}>
            {loading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
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
