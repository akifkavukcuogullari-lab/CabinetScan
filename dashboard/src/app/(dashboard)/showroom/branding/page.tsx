'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Upload, Palette } from 'lucide-react'

export default function BrandingPage() {
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [showroomId, setShowroomId] = useState<string | null>(null)

  const [formData, setFormData] = useState({
    logoUrl: '',
    logoDarkUrl: '',
    primaryColor: '#2563EB',
    secondaryColor: '#1E40AF',
    accentColor: '#3B82F6',
    backgroundColor: '#FFFFFF',
    textColor: '#1F2937',
    welcomeMessage: '',
    thankYouMessage: '',
    termsUrl: '',
    privacyUrl: '',
  })

  useEffect(() => {
    async function loadBranding() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user.id)
        .single()

      if (!showroomUser) return

      setShowroomId(showroomUser.showroom_id)

      const { data: branding } = await supabase
        .from('showroom_branding')
        .select('*')
        .eq('showroom_id', showroomUser.showroom_id)
        .single()

      if (branding) {
        setFormData({
          logoUrl: branding.logo_url || '',
          logoDarkUrl: branding.logo_dark_url || '',
          primaryColor: branding.primary_color || '#2563EB',
          secondaryColor: branding.secondary_color || '#1E40AF',
          accentColor: branding.accent_color || '#3B82F6',
          backgroundColor: branding.background_color || '#FFFFFF',
          textColor: branding.text_color || '#1F2937',
          welcomeMessage: branding.welcome_message || '',
          thankYouMessage: branding.thank_you_message || '',
          termsUrl: branding.terms_url || '',
          privacyUrl: branding.privacy_url || '',
        })
      }

      setLoading(false)
    }

    loadBranding()
  }, [supabase])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setFormData((prev) => ({
      ...prev,
      [e.target.name]: e.target.value,
    }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!showroomId) return

    setSaving(true)
    setError(null)
    setSuccess(false)

    try {
      const { error: updateError } = await supabase
        .from('showroom_branding')
        .update({
          logo_url: formData.logoUrl || null,
          logo_dark_url: formData.logoDarkUrl || null,
          primary_color: formData.primaryColor,
          secondary_color: formData.secondaryColor,
          accent_color: formData.accentColor,
          background_color: formData.backgroundColor,
          text_color: formData.textColor,
          welcome_message: formData.welcomeMessage || null,
          thank_you_message: formData.thankYouMessage || null,
          terms_url: formData.termsUrl || null,
          privacy_url: formData.privacyUrl || null,
        })
        .eq('showroom_id', showroomId)

      if (updateError) throw updateError

      setSuccess(true)
      setTimeout(() => setSuccess(false), 3000)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save branding')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-gray-500">Loading...</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Branding</h1>
        <p className="text-gray-500">Customize how your showroom appears in the iOS app</p>
      </div>

      <form onSubmit={handleSubmit}>
        <Tabs defaultValue="logo" className="space-y-6">
          <TabsList>
            <TabsTrigger value="logo">Logo</TabsTrigger>
            <TabsTrigger value="colors">Colors</TabsTrigger>
            <TabsTrigger value="messages">Messages</TabsTrigger>
            <TabsTrigger value="legal">Legal</TabsTrigger>
          </TabsList>

          <TabsContent value="logo">
            <Card>
              <CardHeader>
                <CardTitle>Logo</CardTitle>
                <CardDescription>
                  Upload your showroom logo for the iOS app
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-2">
                  <Label htmlFor="logoUrl">Logo URL (Light Mode)</Label>
                  <div className="flex gap-2">
                    <Input
                      id="logoUrl"
                      name="logoUrl"
                      value={formData.logoUrl}
                      onChange={handleChange}
                      placeholder="https://..."
                    />
                    <Button type="button" variant="outline" size="icon">
                      <Upload className="h-4 w-4" />
                    </Button>
                  </div>
                  {formData.logoUrl && (
                    <div className="mt-2 p-4 bg-white border rounded-lg">
                      <img
                        src={formData.logoUrl}
                        alt="Logo preview"
                        className="max-h-20 object-contain"
                      />
                    </div>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="logoDarkUrl">Logo URL (Dark Mode)</Label>
                  <div className="flex gap-2">
                    <Input
                      id="logoDarkUrl"
                      name="logoDarkUrl"
                      value={formData.logoDarkUrl}
                      onChange={handleChange}
                      placeholder="https://..."
                    />
                    <Button type="button" variant="outline" size="icon">
                      <Upload className="h-4 w-4" />
                    </Button>
                  </div>
                  {formData.logoDarkUrl && (
                    <div className="mt-2 p-4 bg-gray-900 border rounded-lg">
                      <img
                        src={formData.logoDarkUrl}
                        alt="Logo preview (dark)"
                        className="max-h-20 object-contain"
                      />
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="colors">
            <Card>
              <CardHeader>
                <CardTitle>Brand Colors</CardTitle>
                <CardDescription>
                  Customize the app appearance with your brand colors
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="primaryColor">Primary Color</Label>
                    <div className="flex gap-2">
                      <Input
                        type="color"
                        id="primaryColor"
                        name="primaryColor"
                        value={formData.primaryColor}
                        onChange={handleChange}
                        className="w-12 h-10 p-1"
                      />
                      <Input
                        value={formData.primaryColor}
                        onChange={handleChange}
                        name="primaryColor"
                        className="flex-1"
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="secondaryColor">Secondary Color</Label>
                    <div className="flex gap-2">
                      <Input
                        type="color"
                        id="secondaryColor"
                        name="secondaryColor"
                        value={formData.secondaryColor}
                        onChange={handleChange}
                        className="w-12 h-10 p-1"
                      />
                      <Input
                        value={formData.secondaryColor}
                        onChange={handleChange}
                        name="secondaryColor"
                        className="flex-1"
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="accentColor">Accent Color</Label>
                    <div className="flex gap-2">
                      <Input
                        type="color"
                        id="accentColor"
                        name="accentColor"
                        value={formData.accentColor}
                        onChange={handleChange}
                        className="w-12 h-10 p-1"
                      />
                      <Input
                        value={formData.accentColor}
                        onChange={handleChange}
                        name="accentColor"
                        className="flex-1"
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="textColor">Text Color</Label>
                    <div className="flex gap-2">
                      <Input
                        type="color"
                        id="textColor"
                        name="textColor"
                        value={formData.textColor}
                        onChange={handleChange}
                        className="w-12 h-10 p-1"
                      />
                      <Input
                        value={formData.textColor}
                        onChange={handleChange}
                        name="textColor"
                        className="flex-1"
                      />
                    </div>
                  </div>
                </div>

                {/* Preview */}
                <div className="mt-6 p-6 rounded-lg border" style={{ backgroundColor: formData.backgroundColor }}>
                  <h3 className="text-lg font-bold" style={{ color: formData.primaryColor }}>
                    Preview
                  </h3>
                  <p style={{ color: formData.textColor }}>
                    This is how your brand colors will appear in the app.
                  </p>
                  <button
                    type="button"
                    className="mt-2 px-4 py-2 rounded-md text-white"
                    style={{ backgroundColor: formData.accentColor }}
                  >
                    Sample Button
                  </button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="messages">
            <Card>
              <CardHeader>
                <CardTitle>Custom Messages</CardTitle>
                <CardDescription>
                  Personalize the messages customers see in the app
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="welcomeMessage">Welcome Message</Label>
                  <textarea
                    id="welcomeMessage"
                    name="welcomeMessage"
                    value={formData.welcomeMessage}
                    onChange={handleChange}
                    placeholder="Welcome to our showroom! Let's get started with your project."
                    className="w-full min-h-[100px] px-3 py-2 rounded-md border border-input bg-background text-sm"
                  />
                  <p className="text-xs text-gray-500">
                    Shown when customers first enter your showroom code
                  </p>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="thankYouMessage">Thank You Message</Label>
                  <textarea
                    id="thankYouMessage"
                    name="thankYouMessage"
                    value={formData.thankYouMessage}
                    onChange={handleChange}
                    placeholder="Thank you for your submission! We'll review your project and get back to you soon."
                    className="w-full min-h-[100px] px-3 py-2 rounded-md border border-input bg-background text-sm"
                  />
                  <p className="text-xs text-gray-500">
                    Shown after customers submit their project
                  </p>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="legal">
            <Card>
              <CardHeader>
                <CardTitle>Legal Links</CardTitle>
                <CardDescription>
                  Links to your terms of service and privacy policy
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="termsUrl">Terms of Service URL</Label>
                  <Input
                    id="termsUrl"
                    name="termsUrl"
                    type="url"
                    value={formData.termsUrl}
                    onChange={handleChange}
                    placeholder="https://yoursite.com/terms"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="privacyUrl">Privacy Policy URL</Label>
                  <Input
                    id="privacyUrl"
                    name="privacyUrl"
                    type="url"
                    value={formData.privacyUrl}
                    onChange={handleChange}
                    placeholder="https://yoursite.com/privacy"
                  />
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {error && (
          <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md mt-4">
            {error}
          </div>
        )}

        {success && (
          <div className="p-3 text-sm text-green-600 bg-green-50 rounded-md mt-4">
            Branding saved successfully!
          </div>
        )}

        <div className="flex justify-end mt-6">
          <Button type="submit" disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      </form>
    </div>
  )
}
