'use client'

import { useState, useEffect, useRef } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Upload, Loader2, X, Lock, Sparkles } from 'lucide-react'
import { useSubscriptionContext } from '@/contexts/subscription-context'

export default function BrandingPage() {
  const supabase = createClient()
  const logoInputRef = useRef<HTMLInputElement>(null)
  const logoDarkInputRef = useRef<HTMLInputElement>(null)
  const { canUseFeature } = useSubscriptionContext()

  // Check if custom branding (logo upload) is available
  const canUseBranding = canUseFeature('customBranding')

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [uploadingLogo, setUploadingLogo] = useState(false)
  const [uploadingLogoDark, setUploadingLogoDark] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [showroomId, setShowroomId] = useState<string | null>(null)

  const [formData, setFormData] = useState({
    logoUrl: '',
    logoDarkUrl: '',
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
        .select('logo_url, logo_dark_url')
        .eq('showroom_id', showroomUser.showroom_id)
        .single()

      if (branding) {
        setFormData({
          logoUrl: branding.logo_url || '',
          logoDarkUrl: branding.logo_dark_url || '',
        })
      }

      setLoading(false)
    }

    loadBranding()
  }, [supabase])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData((prev) => ({
      ...prev,
      [e.target.name]: e.target.value,
    }))
  }

  const handleLogoUpload = async (e: React.ChangeEvent<HTMLInputElement>, isDark: boolean) => {
    const file = e.target.files?.[0]
    if (!file || !showroomId) return

    const setUploading = isDark ? setUploadingLogoDark : setUploadingLogo
    setUploading(true)
    setError(null)

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${showroomId}/${isDark ? 'logo-dark' : 'logo'}-${Date.now()}.${fileExt}`

      const { error: uploadError } = await supabase.storage
        .from('logos')
        .upload(fileName, file, { upsert: true })

      if (uploadError) {
        console.error('Upload error details:', JSON.stringify(uploadError, null, 2))
        throw new Error(uploadError.message || 'Upload failed')
      }

      const { data: { publicUrl } } = supabase.storage.from('logos').getPublicUrl(fileName)

      setFormData((prev) => ({
        ...prev,
        [isDark ? 'logoDarkUrl' : 'logoUrl']: publicUrl,
      }))
    } catch (err) {
      console.error('Error uploading logo:', err)
      const errorMessage = err instanceof Error ? err.message : 'Unknown error'
      setError(`Failed to upload logo: ${errorMessage}`)
    } finally {
      setUploading(false)
    }
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
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              Logo
              {!canUseBranding && <Lock className="h-4 w-4 text-gray-400" />}
            </CardTitle>
            <CardDescription>
              Upload your showroom logo for the iOS app
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Upgrade prompt for Starter plan */}
            {!canUseBranding && (
              <div className="p-6 bg-gray-50 border-2 border-dashed border-gray-300 rounded-lg text-center">
                <div className="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center mx-auto mb-4">
                  <Lock className="h-8 w-8 text-gray-400" />
                </div>
                <h3 className="text-lg font-medium text-gray-900 mb-2">Custom Logo Not Available</h3>
                <p className="text-sm text-gray-600 mb-4 max-w-md mx-auto">
                  White-labeling with custom logos is available on Pro plan and above.
                  Upgrade to display your showroom&apos;s logo in the iOS app.
                </p>
                <Button asChild>
                  <Link href="/showroom/billing">
                    <Sparkles className="h-4 w-4 mr-2" />
                    Upgrade to Pro
                  </Link>
                </Button>
              </div>
            )}

            {/* Logo upload section - only shown for Pro+ */}
            {canUseBranding && (
              <>
                {/* Logo dimension guidelines */}
                <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
                  <p className="text-sm font-medium text-blue-800 mb-2">Recommended Logo Specifications</p>
                  <div className="grid grid-cols-2 gap-4 mt-3">
                    <div>
                      <p className="text-xs font-semibold text-blue-900 uppercase tracking-wide">Ideal Size</p>
                      <p className="text-lg font-bold text-blue-800">1000 x 400 px</p>
                    </div>
                    <div>
                      <p className="text-xs font-semibold text-blue-900 uppercase tracking-wide">Aspect Ratio</p>
                      <p className="text-lg font-bold text-blue-800">2:1 to 4:1</p>
                    </div>
                  </div>
                  <ul className="text-sm text-blue-700 space-y-1 mt-3">
                    <li><strong>Width:</strong> 800 - 1200 pixels (horizontal/wide logos work best)</li>
                    <li><strong>Height:</strong> 300 - 500 pixels</li>
                    <li><strong>Format:</strong> PNG with transparent background (recommended)</li>
                    <li><strong>File size:</strong> Under 300KB for fast loading</li>
                  </ul>
                  <p className="text-xs text-blue-600 mt-3 italic">
                    These dimensions ensure your logo displays crisp and clear on all iPhone models including 3x Retina displays.
                  </p>
                </div>

                {/* Hidden file inputs */}
                <input
                  type="file"
                  ref={logoInputRef}
                  className="hidden"
                  accept="image/*"
                  onChange={(e) => handleLogoUpload(e, false)}
                />
                <input
                  type="file"
                  ref={logoDarkInputRef}
                  className="hidden"
                  accept="image/*"
                  onChange={(e) => handleLogoUpload(e, true)}
                />

                <div className="space-y-2">
                  <Label htmlFor="logoUrl">Logo (Light Mode)</Label>
                  {formData.logoUrl ? (
                    <div className="relative inline-block">
                      <div className="p-4 bg-white border rounded-lg">
                        <img
                          src={formData.logoUrl}
                          alt="Logo preview"
                          className="max-h-24 object-contain"
                        />
                      </div>
                      <Button
                        type="button"
                        variant="destructive"
                        size="icon"
                        className="absolute -top-2 -right-2 h-6 w-6"
                        onClick={() => setFormData((prev) => ({ ...prev, logoUrl: '' }))}
                      >
                        <X className="h-3 w-3" />
                      </Button>
                    </div>
                  ) : (
                    <div
                      onClick={() => logoInputRef.current?.click()}
                      className="flex flex-col items-center justify-center w-full h-32 border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50 transition-colors"
                    >
                      {uploadingLogo ? (
                        <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
                      ) : (
                        <>
                          <Upload className="h-8 w-8 text-gray-400 mb-2" />
                          <p className="text-sm text-gray-500">Click to upload logo</p>
                          <p className="text-xs text-gray-400">PNG, JPG, SVG</p>
                        </>
                      )}
                    </div>
                  )}
                  <p className="text-xs text-gray-500">
                    Or enter a URL:
                  </p>
                  <Input
                    id="logoUrl"
                    name="logoUrl"
                    value={formData.logoUrl}
                    onChange={handleChange}
                    placeholder="https://..."
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="logoDarkUrl">Logo (Dark Mode) - Optional</Label>
                  {formData.logoDarkUrl ? (
                    <div className="relative inline-block">
                      <div className="p-4 bg-gray-900 border rounded-lg">
                        <img
                          src={formData.logoDarkUrl}
                          alt="Logo preview (dark)"
                          className="max-h-24 object-contain"
                        />
                      </div>
                      <Button
                        type="button"
                        variant="destructive"
                        size="icon"
                        className="absolute -top-2 -right-2 h-6 w-6"
                        onClick={() => setFormData((prev) => ({ ...prev, logoDarkUrl: '' }))}
                      >
                        <X className="h-3 w-3" />
                      </Button>
                    </div>
                  ) : (
                    <div
                      onClick={() => logoDarkInputRef.current?.click()}
                      className="flex flex-col items-center justify-center w-full h-32 border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50 transition-colors"
                    >
                      {uploadingLogoDark ? (
                        <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
                      ) : (
                        <>
                          <Upload className="h-8 w-8 text-gray-400 mb-2" />
                          <p className="text-sm text-gray-500">Click to upload dark mode logo</p>
                          <p className="text-xs text-gray-400">PNG, JPG, SVG</p>
                        </>
                      )}
                    </div>
                  )}
                  <p className="text-xs text-gray-500">
                    Or enter a URL:
                  </p>
                  <Input
                    id="logoDarkUrl"
                    name="logoDarkUrl"
                    value={formData.logoDarkUrl}
                    onChange={handleChange}
                    placeholder="https://..."
                  />
                </div>
              </>
            )}
          </CardContent>
        </Card>

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

        {canUseBranding && (
          <div className="flex justify-end mt-6">
            <Button type="submit" disabled={saving}>
              {saving ? 'Saving...' : 'Save Changes'}
            </Button>
          </div>
        )}
      </form>
    </div>
  )
}
