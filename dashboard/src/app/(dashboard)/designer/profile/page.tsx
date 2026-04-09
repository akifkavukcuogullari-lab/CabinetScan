'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Loader2, Save, User } from 'lucide-react'
import { toast } from 'sonner'

interface DesignerProfile {
  id: string
  user_id: string
  email: string
  full_name: string
  avatar_url: string | null
  bio: string | null
  is_active: boolean
  created_at: string
}

export default function DesignerProfilePage() {
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<DesignerProfile | null>(null)

  const [formData, setFormData] = useState({
    full_name: '',
    bio: '',
    avatar_url: '',
  })

  useEffect(() => {
    async function loadProfile() {
      try {
        const { data: { user } } = await supabase.auth.getUser()

        if (!user) {
          setLoading(false)
          return
        }

        const { data, error } = await supabase
          .from('designers')
          .select('*')
          .eq('user_id', user.id)
          .single()

        if (error) {
          console.error('Failed to load designer profile:', error)
          toast.error('Failed to load profile')
          setLoading(false)
          return
        }

        setProfile(data)
        setFormData({
          full_name: data.full_name || '',
          bio: data.bio || '',
          avatar_url: data.avatar_url || '',
        })
      } catch (err) {
        console.error('Failed to load profile:', err)
        toast.error('Failed to load profile')
      } finally {
        setLoading(false)
      }
    }

    loadProfile()
  }, [supabase])

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!profile) return

    if (!formData.full_name.trim()) {
      toast.error('Full name is required')
      return
    }

    setSaving(true)

    try {
      const { error } = await supabase
        .from('designers')
        .update({
          full_name: formData.full_name.trim(),
          bio: formData.bio.trim() || null,
          avatar_url: formData.avatar_url.trim() || null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', profile.id)

      if (error) {
        console.error('Failed to update profile:', error)
        toast.error('Failed to save profile')
        return
      }

      setProfile((prev) =>
        prev
          ? {
              ...prev,
              full_name: formData.full_name.trim(),
              bio: formData.bio.trim() || null,
              avatar_url: formData.avatar_url.trim() || null,
            }
          : null
      )

      toast.success('Profile updated successfully')
    } catch (err) {
      console.error('Failed to save profile:', err)
      toast.error('An error occurred while saving')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="p-6">
        <h1 className="text-2xl font-bold mb-6">Profile</h1>
        <Card>
          <CardContent className="flex items-center justify-center py-12">
            <Loader2 className="h-8 w-8 animate-spin text-blue-600" />
          </CardContent>
        </Card>
      </div>
    )
  }

  if (!profile) {
    return (
      <div className="p-6">
        <h1 className="text-2xl font-bold mb-6">Profile</h1>
        <Card>
          <CardContent className="py-10 text-center text-gray-500">
            Unable to load profile. Please try refreshing the page.
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="p-6 max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">Profile</h1>

      <form onSubmit={handleSave} className="space-y-6">
        {/* Avatar preview */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Avatar</CardTitle>
            <CardDescription>
              Your profile picture shown to showroom owners
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-4">
              {formData.avatar_url ? (
                <img
                  src={formData.avatar_url}
                  alt={formData.full_name}
                  className="h-16 w-16 rounded-full object-cover border"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none'
                  }}
                />
              ) : (
                <div className="h-16 w-16 rounded-full bg-gray-100 flex items-center justify-center border">
                  <User className="h-8 w-8 text-gray-400" />
                </div>
              )}
              <div className="flex-1 space-y-2">
                <Label htmlFor="avatar_url">Avatar URL</Label>
                <Input
                  id="avatar_url"
                  type="url"
                  placeholder="https://example.com/avatar.jpg"
                  value={formData.avatar_url}
                  onChange={(e) =>
                    setFormData((prev) => ({ ...prev, avatar_url: e.target.value }))
                  }
                />
                <p className="text-xs text-muted-foreground">
                  Paste a URL to an image. Square images work best.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Profile info */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Personal Information</CardTitle>
            <CardDescription>
              Update your name and bio
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={profile.email}
                disabled
                className="bg-gray-50"
              />
              <p className="text-xs text-muted-foreground">
                Email cannot be changed. Contact an administrator if you need to update it.
              </p>
            </div>

            <div className="space-y-2">
              <Label htmlFor="full_name">Full Name</Label>
              <Input
                id="full_name"
                type="text"
                placeholder="Your full name"
                value={formData.full_name}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, full_name: e.target.value }))
                }
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="bio">Bio</Label>
              <Textarea
                id="bio"
                placeholder="Tell showroom owners about your design experience, specialties, and style..."
                value={formData.bio}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, bio: e.target.value }))
                }
                rows={4}
              />
              <p className="text-xs text-muted-foreground">
                This will be visible to showroom owners when they view your profile.
              </p>
            </div>
          </CardContent>
        </Card>

        {/* Account info (read-only) */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Account</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Status</span>
              <span className={profile.is_active ? 'text-green-600 font-medium' : 'text-gray-500'}>
                {profile.is_active ? 'Active' : 'Inactive'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Joined</span>
              <span>{new Date(profile.created_at).toLocaleDateString()}</span>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end">
          <Button type="submit" disabled={saving}>
            {saving ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Saving...
              </>
            ) : (
              <>
                <Save className="mr-2 h-4 w-4" />
                Save Changes
              </>
            )}
          </Button>
        </div>
      </form>
    </div>
  )
}
