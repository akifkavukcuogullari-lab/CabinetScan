'use client'

import { useState, useEffect } from 'react'
import { useRouter, useParams } from 'next/navigation'
import Link from 'next/link'
import { toast } from 'sonner'
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
import { ArrowLeft, Loader2, AlertCircle, Save } from 'lucide-react'

interface ShowroomData {
  id: string
  name: string
  email: string
  phone: string | null
  address_line1: string | null
  address_line2: string | null
  city: string | null
  state: string | null
  postal_code: string | null
  showroom_code: string
  slug: string
}

export default function EditShowroomPage() {
  const router = useRouter()
  const params = useParams()
  const showroomId = params.id as string
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showroom, setShowroom] = useState<ShowroomData | null>(null)

  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    addressLine1: '',
    addressLine2: '',
    city: '',
    state: '',
    postalCode: '',
  })

  useEffect(() => {
    async function loadShowroom() {
      const { data, error: fetchError } = await supabase
        .from('showrooms')
        .select('*')
        .eq('id', showroomId)
        .single()

      if (fetchError || !data) {
        setError('Showroom not found')
        setLoading(false)
        return
      }

      setShowroom(data)
      setFormData({
        name: data.name || '',
        email: data.email || '',
        phone: data.phone || '',
        addressLine1: data.address_line1 || '',
        addressLine2: data.address_line2 || '',
        city: data.city || '',
        state: data.state || '',
        postalCode: data.postal_code || '',
      })
      setLoading(false)
    }

    loadShowroom()
  }, [showroomId, supabase])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData((prev) => ({
      ...prev,
      [e.target.name]: e.target.value,
    }))
    if (error) setError(null)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setError(null)

    try {
      const { error: updateError } = await supabase
        .from('showrooms')
        .update({
          name: formData.name,
          email: formData.email,
          phone: formData.phone || null,
          address_line1: formData.addressLine1 || null,
          address_line2: formData.addressLine2 || null,
          city: formData.city || null,
          state: formData.state || null,
          postal_code: formData.postalCode || null,
        })
        .eq('id', showroomId)

      if (updateError) {
        throw updateError
      }

      toast.success('Showroom updated', {
        description: 'Changes have been saved successfully.',
      })
      router.push(`/admin/showrooms/${showroomId}`)
    } catch (err) {
      console.error('Failed to update showroom:', err)
      setError('Failed to update showroom. Please try again.')
      toast.error('Update failed', {
        description: 'Could not save changes. Please try again.',
      })
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-blue-600" />
      </div>
    )
  }

  if (!showroom) {
    return (
      <div className="max-w-2xl mx-auto">
        <Card>
          <CardContent className="py-10 text-center">
            <AlertCircle className="h-12 w-12 mx-auto text-red-500 mb-4" />
            <h3 className="text-lg font-medium mb-2">Showroom Not Found</h3>
            <p className="text-gray-500 mb-4">
              The showroom you're trying to edit doesn't exist.
            </p>
            <Link href="/admin/showrooms">
              <Button>Back to Showrooms</Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Link href={`/admin/showrooms/${showroomId}`}>
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold">Edit Showroom</h1>
          <p className="text-gray-500">{showroom.name}</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Showroom Details</CardTitle>
            <CardDescription>Update showroom information</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {error && (
              <div className="p-4 rounded-lg bg-red-50 border border-red-200">
                <div className="flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-red-600 mt-0.5" />
                  <p className="text-sm text-red-800">{error}</p>
                </div>
              </div>
            )}

            {/* Read-only fields */}
            <div className="p-4 bg-gray-50 rounded-lg space-y-3">
              <div>
                <Label className="text-xs text-gray-500">Showroom Code</Label>
                <p className="font-mono text-lg font-bold">{showroom.showroom_code}</p>
              </div>
              <div>
                <Label className="text-xs text-gray-500">URL Slug</Label>
                <p className="font-mono text-sm">{showroom.slug}</p>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="name">
                Showroom Name <span className="text-red-500">*</span>
              </Label>
              <Input
                id="name"
                name="name"
                value={formData.name}
                onChange={handleChange}
                required
                disabled={saving}
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
                required
                disabled={saving}
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
                disabled={saving}
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
                disabled={saving}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="addressLine2">Address Line 2</Label>
              <Input
                id="addressLine2"
                name="addressLine2"
                value={formData.addressLine2}
                onChange={handleChange}
                disabled={saving}
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
                  disabled={saving}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="state">State</Label>
                <Input
                  id="state"
                  name="state"
                  value={formData.state}
                  onChange={handleChange}
                  disabled={saving}
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
                disabled={saving}
              />
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-4 mt-6">
          <Link href={`/admin/showrooms/${showroomId}`}>
            <Button variant="outline" type="button" disabled={saving}>
              Cancel
            </Button>
          </Link>
          <Button type="submit" disabled={saving} className="gap-2">
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
      </form>
    </div>
  )
}
