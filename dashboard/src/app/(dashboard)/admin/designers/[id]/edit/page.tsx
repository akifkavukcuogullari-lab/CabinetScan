'use client'

import { useState, useEffect } from 'react'
import { useRouter, useParams } from 'next/navigation'
import Link from 'next/link'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { ArrowLeft, Loader2, AlertCircle, Save, User } from 'lucide-react'

interface DesignerData {
  id: string
  full_name: string
  email: string
  bio: string | null
  avatar_url: string | null
  is_active: boolean
}

export default function EditDesignerPage() {
  const router = useRouter()
  const params = useParams()
  const designerId = params.id as string
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [designer, setDesigner] = useState<DesignerData | null>(null)

  const [formData, setFormData] = useState({
    fullName: '',
    email: '',
    bio: '',
    avatarUrl: '',
    isActive: true,
  })

  useEffect(() => {
    async function loadDesigner() {
      const { data, error: fetchError } = await supabase
        .from('designers')
        .select('*')
        .eq('id', designerId)
        .single()

      if (fetchError || !data) {
        setError('Designer not found')
        setLoading(false)
        return
      }

      setDesigner(data)
      setFormData({
        fullName: data.full_name || '',
        email: data.email || '',
        bio: data.bio || '',
        avatarUrl: data.avatar_url || '',
        isActive: data.is_active ?? true,
      })
      setLoading(false)
    }

    loadDesigner()
  }, [designerId, supabase])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
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
        .from('designers')
        .update({
          full_name: formData.fullName,
          email: formData.email,
          bio: formData.bio || null,
          avatar_url: formData.avatarUrl || null,
          is_active: formData.isActive,
        })
        .eq('id', designerId)

      if (updateError) {
        throw updateError
      }

      toast.success('Designer updated', {
        description: 'Changes have been saved successfully.',
      })
      router.push(`/admin/designers/${designerId}`)
    } catch (err) {
      console.error('Failed to update designer:', err)
      setError('Failed to update designer. Please try again.')
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

  if (!designer) {
    return (
      <div className="max-w-2xl mx-auto">
        <Card>
          <CardContent className="py-10 text-center">
            <AlertCircle className="h-12 w-12 mx-auto text-red-500 mb-4" />
            <h3 className="text-lg font-medium mb-2">Designer Not Found</h3>
            <p className="text-gray-500 mb-4">
              The designer you are trying to edit does not exist.
            </p>
            <Link href="/admin/designers">
              <Button>Back to Designers</Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Link href={`/admin/designers/${designerId}`}>
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold">Edit Designer</h1>
          <p className="text-gray-500">{designer.full_name}</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Designer Details</CardTitle>
            <CardDescription>Update designer profile information</CardDescription>
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

            <div className="space-y-2">
              <Label htmlFor="fullName">
                Full Name <span className="text-red-500">*</span>
              </Label>
              <Input
                id="fullName"
                name="fullName"
                value={formData.fullName}
                onChange={handleChange}
                required
                disabled={saving}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">
                Email <span className="text-red-500">*</span>
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
              <Label htmlFor="bio">Bio</Label>
              <Textarea
                id="bio"
                name="bio"
                value={formData.bio}
                onChange={handleChange}
                disabled={saving}
                rows={4}
                placeholder="A brief description about the designer..."
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="avatarUrl">Avatar URL</Label>
              <Input
                id="avatarUrl"
                name="avatarUrl"
                value={formData.avatarUrl}
                onChange={handleChange}
                disabled={saving}
                placeholder="https://example.com/avatar.jpg"
              />
              {formData.avatarUrl && (
                <div className="mt-2 flex items-center gap-3">
                  <img
                    src={formData.avatarUrl}
                    alt="Avatar preview"
                    className="h-16 w-16 rounded-full object-cover border-2 border-gray-100"
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = 'none'
                    }}
                  />
                  <p className="text-xs text-gray-500">Preview</p>
                </div>
              )}
            </div>

            <div className="flex items-center justify-between rounded-lg border p-4">
              <div className="space-y-0.5">
                <Label htmlFor="is-active">Active Status</Label>
                <p className="text-sm text-gray-500">
                  {formData.isActive
                    ? 'Designer can receive new project assignments'
                    : 'Designer will not receive new project assignments'}
                </p>
              </div>
              <Switch
                id="is-active"
                checked={formData.isActive}
                onCheckedChange={(checked) =>
                  setFormData((prev) => ({ ...prev, isActive: checked }))
                }
                disabled={saving}
              />
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-4 mt-6">
          <Link href={`/admin/designers/${designerId}`}>
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
