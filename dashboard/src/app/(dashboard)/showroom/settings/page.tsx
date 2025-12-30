'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useSubscriptionContext } from '@/contexts/subscription-context'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { Switch } from '@/components/ui/switch'
import { Webhook, CheckCircle, AlertCircle, Loader2, Lock, Sparkles, ChevronDown, ChevronUp, Edit2, RefreshCw, Save, X } from 'lucide-react'
import Link from 'next/link'

interface Category {
  id: string
  name: string
  slug: string
  pricing_unit: string
  display_order: number
}

interface ShowroomCategory {
  id: string
  category_id: string
  is_enabled: boolean
  display_order: number
  is_required: boolean
  custom_name: string | null
}

export default function SettingsPage() {
  const supabase = createClient()
  const { canUseFeature, getUpgradeReason } = useSubscriptionContext()

  const canUseWebhooks = canUseFeature('webhookAccess')

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [showroomId, setShowroomId] = useState<string | null>(null)
  const [showroom, setShowroom] = useState<any>(null)
  const [categories, setCategories] = useState<Category[]>([])
  const [showroomCategories, setShowroomCategories] = useState<ShowroomCategory[]>([])
  const [webhookUrl, setWebhookUrl] = useState('')
  const [webhookSaving, setWebhookSaving] = useState(false)
  const [webhookSuccess, setWebhookSuccess] = useState(false)
  const [webhookError, setWebhookError] = useState<string | null>(null)
  const [quoteWebhookUrl, setQuoteWebhookUrl] = useState('')
  const [quoteWebhookSaving, setQuoteWebhookSaving] = useState(false)
  const [quoteWebhookSuccess, setQuoteWebhookSuccess] = useState(false)
  const [quoteWebhookError, setQuoteWebhookError] = useState<string | null>(null)
  const [showWebhookExample, setShowWebhookExample] = useState(false)
  const [showQuoteWebhookExample, setShowQuoteWebhookExample] = useState(false)

  // Showroom info editing state
  const [isEditingInfo, setIsEditingInfo] = useState(false)
  const [showroomName, setShowroomName] = useState('')
  const [showroomCode, setShowroomCode] = useState('')
  const [showroomEmail, setShowroomEmail] = useState('')
  const [showroomPhone, setShowroomPhone] = useState('')
  const [infoSaving, setInfoSaving] = useState(false)
  const [infoError, setInfoError] = useState<string | null>(null)
  const [infoSuccess, setInfoSuccess] = useState(false)

  useEffect(() => {
    async function loadData() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user.id)
        .single()

      if (!showroomUser) return

      setShowroomId(showroomUser.showroom_id)

      // Load showroom details
      const { data: showroomData } = await supabase
        .from('showrooms')
        .select('*')
        .eq('id', showroomUser.showroom_id)
        .single()

      if (showroomData) {
        setShowroom(showroomData)
        setWebhookUrl(showroomData.webhook_url || '')
        setQuoteWebhookUrl(showroomData.quote_webhook_url || '')
        // Initialize edit form
        setShowroomName(showroomData.name || '')
        setShowroomCode(showroomData.showroom_code || '')
        setShowroomEmail(showroomData.email || '')
        setShowroomPhone(showroomData.phone || '')
      }

      // Load all categories
      const { data: categoriesData } = await supabase
        .from('categories')
        .select('*')
        .eq('is_active', true)
        .order('display_order')

      if (categoriesData) setCategories(categoriesData)

      // Load showroom categories
      const { data: showroomCategoriesData } = await supabase
        .from('showroom_categories')
        .select('*')
        .eq('showroom_id', showroomUser.showroom_id)

      if (showroomCategoriesData) setShowroomCategories(showroomCategoriesData)

      setLoading(false)
    }

    loadData()
  }, [supabase])

  const getCategorySettings = (categoryId: string): ShowroomCategory | undefined => {
    return showroomCategories.find((sc) => sc.category_id === categoryId)
  }

  const toggleCategory = async (categoryId: string, enabled: boolean) => {
    if (!showroomId) return

    const existing = getCategorySettings(categoryId)

    if (existing) {
      // Update existing
      await supabase
        .from('showroom_categories')
        .update({ is_enabled: enabled })
        .eq('id', existing.id)

      setShowroomCategories((prev) =>
        prev.map((sc) =>
          sc.category_id === categoryId ? { ...sc, is_enabled: enabled } : sc
        )
      )
    } else {
      // Create new
      const category = categories.find((c) => c.id === categoryId)
      const { data } = await supabase
        .from('showroom_categories')
        .insert({
          showroom_id: showroomId,
          category_id: categoryId,
          is_enabled: enabled,
          display_order: category?.display_order || 0,
        })
        .select()
        .single()

      if (data) {
        setShowroomCategories((prev) => [...prev, data])
      }
    }
  }

  const toggleRequired = async (categoryId: string, required: boolean) => {
    const existing = getCategorySettings(categoryId)
    if (!existing) return

    await supabase
      .from('showroom_categories')
      .update({ is_required: required })
      .eq('id', existing.id)

    setShowroomCategories((prev) =>
      prev.map((sc) =>
        sc.category_id === categoryId ? { ...sc, is_required: required } : sc
      )
    )
  }

  const validateWebhookUrl = (url: string): boolean => {
    if (!url) return true
    try {
      const parsed = new URL(url)
      return parsed.protocol === 'https:' || parsed.protocol === 'http:'
    } catch {
      return false
    }
  }

  const saveWebhookUrl = async () => {
    if (!showroomId) return

    if (webhookUrl && !validateWebhookUrl(webhookUrl)) {
      setWebhookError('Please enter a valid URL (must start with http:// or https://)')
      return
    }

    setWebhookSaving(true)
    setWebhookError(null)
    setWebhookSuccess(false)

    const { error } = await supabase
      .from('showrooms')
      .update({ webhook_url: webhookUrl || null })
      .eq('id', showroomId)

    setWebhookSaving(false)

    if (error) {
      setWebhookError('Failed to save webhook URL')
    } else {
      setWebhookSuccess(true)
      setTimeout(() => setWebhookSuccess(false), 3000)
    }
  }

  const saveQuoteWebhookUrl = async () => {
    if (!showroomId) return

    if (quoteWebhookUrl && !validateWebhookUrl(quoteWebhookUrl)) {
      setQuoteWebhookError('Please enter a valid URL (must start with http:// or https://)')
      return
    }

    setQuoteWebhookSaving(true)
    setQuoteWebhookError(null)
    setQuoteWebhookSuccess(false)

    const { error } = await supabase
      .from('showrooms')
      .update({ quote_webhook_url: quoteWebhookUrl || null })
      .eq('id', showroomId)

    setQuoteWebhookSaving(false)

    if (error) {
      setQuoteWebhookError('Failed to save quote webhook URL')
    } else {
      setQuoteWebhookSuccess(true)
      setTimeout(() => setQuoteWebhookSuccess(false), 3000)
    }
  }

  const generateShowroomCode = () => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // Exclude confusing chars (0, O, 1, I)
    let code = ''
    for (let i = 0; i < 6; i++) {
      code += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    setShowroomCode(code)
    setInfoError(null)
  }

  const validateShowroomCode = (code: string): boolean => {
    // Must be 6 characters, uppercase letters and numbers only
    const pattern = /^[A-Z0-9]{6}$/
    return pattern.test(code)
  }

  const checkCodeUnique = async (code: string): Promise<boolean> => {
    if (!showroomId) return false

    const { data } = await supabase
      .from('showrooms')
      .select('id')
      .eq('showroom_code', code)
      .neq('id', showroomId)
      .single()

    return !data // Code is unique if no data returned
  }

  const saveShowroomInfo = async () => {
    if (!showroomId) return

    // Validate required fields
    if (!showroomName.trim()) {
      setInfoError('Showroom name is required')
      return
    }

    if (!showroomCode.trim()) {
      setInfoError('Showroom code is required')
      return
    }

    if (!showroomEmail.trim()) {
      setInfoError('Email is required')
      return
    }

    // Validate code format
    const upperCode = showroomCode.toUpperCase()
    if (!validateShowroomCode(upperCode)) {
      setInfoError('Showroom code must be 6 characters (letters and numbers only)')
      return
    }

    // Check if code changed and if it's unique
    if (upperCode !== showroom?.showroom_code) {
      const isUnique = await checkCodeUnique(upperCode)
      if (!isUnique) {
        setInfoError('This showroom code is already in use. Please choose another.')
        return
      }
    }

    setInfoSaving(true)
    setInfoError(null)
    setInfoSuccess(false)

    const { error } = await supabase
      .from('showrooms')
      .update({
        name: showroomName.trim(),
        showroom_code: upperCode,
        email: showroomEmail.trim(),
        phone: showroomPhone.trim() || null,
      })
      .eq('id', showroomId)

    setInfoSaving(false)

    if (error) {
      setInfoError('Failed to save showroom information')
    } else {
      // Update local state
      setShowroom({
        ...showroom,
        name: showroomName.trim(),
        showroom_code: upperCode,
        email: showroomEmail.trim(),
        phone: showroomPhone.trim() || null,
      })
      setShowroomCode(upperCode) // Update to uppercase
      setInfoSuccess(true)
      setIsEditingInfo(false)
      setTimeout(() => setInfoSuccess(false), 3000)
    }
  }

  const cancelEditInfo = () => {
    setShowroomName(showroom?.name || '')
    setShowroomCode(showroom?.showroom_code || '')
    setShowroomEmail(showroom?.email || '')
    setShowroomPhone(showroom?.phone || '')
    setInfoError(null)
    setIsEditingInfo(false)
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
        <h1 className="text-2xl font-bold">Settings</h1>
        <p className="text-gray-500">Configure your showroom settings</p>
      </div>

      {/* Showroom Info */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Showroom Information</CardTitle>
              <CardDescription>Your showroom details</CardDescription>
            </div>
            {!isEditingInfo && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => setIsEditingInfo(true)}
              >
                <Edit2 className="h-4 w-4 mr-2" />
                Edit
              </Button>
            )}
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {isEditingInfo ? (
            <>
              {/* Edit Mode */}
              <div className="space-y-4">
                <div>
                  <Label htmlFor="showroom-name">Showroom Name</Label>
                  <Input
                    id="showroom-name"
                    value={showroomName}
                    onChange={(e) => {
                      setShowroomName(e.target.value)
                      setInfoError(null)
                    }}
                    placeholder="Enter showroom name"
                  />
                </div>

                <div>
                  <Label htmlFor="showroom-code">Showroom Code</Label>
                  <div className="flex gap-2">
                    <Input
                      id="showroom-code"
                      value={showroomCode}
                      onChange={(e) => {
                        setShowroomCode(e.target.value.toUpperCase())
                        setInfoError(null)
                      }}
                      placeholder="6 characters (letters/numbers)"
                      maxLength={6}
                      className="font-mono text-lg"
                    />
                    <Button
                      type="button"
                      variant="outline"
                      onClick={generateShowroomCode}
                      title="Generate new code"
                    >
                      <RefreshCw className="h-4 w-4" />
                    </Button>
                  </div>
                  <p className="text-xs text-gray-500 mt-1">
                    This code is used in the iOS app. Changing it will require customers to use the new code.
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label htmlFor="showroom-email">Email</Label>
                    <Input
                      id="showroom-email"
                      type="email"
                      value={showroomEmail}
                      onChange={(e) => {
                        setShowroomEmail(e.target.value)
                        setInfoError(null)
                      }}
                      placeholder="showroom@example.com"
                    />
                  </div>
                  <div>
                    <Label htmlFor="showroom-phone">Phone</Label>
                    <Input
                      id="showroom-phone"
                      type="tel"
                      value={showroomPhone}
                      onChange={(e) => {
                        setShowroomPhone(e.target.value)
                        setInfoError(null)
                      }}
                      placeholder="(555) 123-4567"
                    />
                  </div>
                </div>

                {infoError && (
                  <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">
                    <AlertCircle className="h-4 w-4 flex-shrink-0" />
                    {infoError}
                  </div>
                )}

                {infoSuccess && (
                  <div className="flex items-center gap-2 text-sm text-green-600 bg-green-50 p-3 rounded-lg">
                    <CheckCircle className="h-4 w-4 flex-shrink-0" />
                    Showroom information updated successfully
                  </div>
                )}

                <div className="flex gap-2 justify-end pt-2">
                  <Button
                    variant="outline"
                    onClick={cancelEditInfo}
                    disabled={infoSaving}
                  >
                    <X className="h-4 w-4 mr-2" />
                    Cancel
                  </Button>
                  <Button
                    onClick={saveShowroomInfo}
                    disabled={infoSaving}
                  >
                    {infoSaving ? (
                      <>
                        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                        Saving...
                      </>
                    ) : (
                      <>
                        <Save className="h-4 w-4 mr-2" />
                        Save Changes
                      </>
                    )}
                  </Button>
                </div>
              </div>
            </>
          ) : (
            <>
              {/* Display Mode */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label className="text-gray-500">Showroom Name</Label>
                  <p className="font-medium">{showroom?.name}</p>
                </div>
                <div>
                  <Label className="text-gray-500">Showroom Code</Label>
                  <p className="font-mono text-lg font-bold">{showroom?.showroom_code}</p>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label className="text-gray-500">Email</Label>
                  <p>{showroom?.email}</p>
                </div>
                <div>
                  <Label className="text-gray-500">Phone</Label>
                  <p>{showroom?.phone || '-'}</p>
                </div>
              </div>
              <div>
                <Label className="text-gray-500">Subscription Status</Label>
                <div className="mt-1">
                  <Badge
                    className={
                      showroom?.subscription_status === 'active'
                        ? 'bg-green-100 text-green-800'
                        : showroom?.subscription_status === 'trial'
                        ? 'bg-yellow-100 text-yellow-800'
                        : 'bg-gray-100 text-gray-800'
                    }
                  >
                    {showroom?.subscription_status}
                  </Badge>
                </div>
              </div>

              {infoSuccess && (
                <div className="flex items-center gap-2 text-sm text-green-600 bg-green-50 p-3 rounded-lg">
                  <CheckCircle className="h-4 w-4 flex-shrink-0" />
                  Showroom information updated successfully
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>

      {/* Categories */}
      <Card>
        <CardHeader>
          <CardTitle>Product Categories</CardTitle>
          <CardDescription>
            Enable or disable categories for your showroom. Customers will only see enabled
            categories in the iOS app.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {categories.map((category) => {
              const settings = getCategorySettings(category.id)
              const isEnabled = settings?.is_enabled ?? false
              const isRequired = settings?.is_required ?? false

              return (
                <div
                  key={category.id}
                  className="flex items-center justify-between py-3 border-b last:border-0"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{category.name}</span>
                      <Badge variant="outline" className="text-xs">
                        {category.pricing_unit.replace('_', ' ')}
                      </Badge>
                    </div>
                    <p className="text-sm text-gray-500">{category.slug}</p>
                  </div>

                  <div className="flex items-center gap-6">
                    <div className="flex items-center gap-2">
                      <Label htmlFor={`required-${category.id}`} className="text-sm text-gray-500">
                        Required
                      </Label>
                      <Switch
                        id={`required-${category.id}`}
                        checked={isRequired}
                        onCheckedChange={(checked) => toggleRequired(category.id, checked)}
                        disabled={!isEnabled}
                      />
                    </div>

                    <div className="flex items-center gap-2">
                      <Label htmlFor={`enabled-${category.id}`} className="text-sm text-gray-500">
                        Enabled
                      </Label>
                      <Switch
                        id={`enabled-${category.id}`}
                        checked={isEnabled}
                        onCheckedChange={(checked) => toggleCategory(category.id, checked)}
                      />
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>

      {/* Project Submission Webhook */}
      <Card className={!canUseWebhooks ? 'border-gray-200 bg-gray-50/50' : ''}>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Webhook className="h-5 w-5" />
            Project Submission Webhook
            {!canUseWebhooks && (
              <Badge variant="secondary" className="ml-2 gap-1">
                <Lock className="h-3 w-3" />
                Pro
              </Badge>
            )}
          </CardTitle>
          <CardDescription>
            Receive project submission data when a customer completes a scan. We&apos;ll send a POST request
            with measurements, 3D model URLs, product selections, and customer information to your endpoint.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {canUseWebhooks ? (
            <>
              <div className="space-y-2">
                <Label htmlFor="webhook-url">Project Submission Webhook URL</Label>
                <div className="flex gap-2">
                  <Input
                    id="webhook-url"
                    type="url"
                    placeholder="https://your-domain.com/api/webhooks/project-submitted"
                    value={webhookUrl}
                    onChange={(e) => {
                      setWebhookUrl(e.target.value)
                      setWebhookError(null)
                    }}
                    className="flex-1"
                  />
                  <Button
                    onClick={saveWebhookUrl}
                    disabled={webhookSaving}
                  >
                    {webhookSaving ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      'Save'
                    )}
                  </Button>
                </div>
                {webhookError && (
                  <div className="flex items-center gap-2 text-sm text-red-600">
                    <AlertCircle className="h-4 w-4" />
                    {webhookError}
                  </div>
                )}
                {webhookSuccess && (
                  <div className="flex items-center gap-2 text-sm text-green-600">
                    <CheckCircle className="h-4 w-4" />
                    Project webhook URL saved successfully
                  </div>
                )}
              </div>

              <Separator />

              <div className="space-y-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowWebhookExample(!showWebhookExample)}
                  className="w-full justify-between"
                >
                  <span className="text-gray-600">View Webhook Payload Example</span>
                  {showWebhookExample ? (
                    <ChevronUp className="h-4 w-4" />
                  ) : (
                    <ChevronDown className="h-4 w-4" />
                  )}
                </Button>
                {showWebhookExample && (
                  <pre className="bg-gray-100 p-4 rounded-lg text-xs overflow-x-auto max-h-96">
{`{
  "event": "project.submitted",
  "timestamp": "2024-01-15T10:30:00Z",
  "project": {
    "id": "uuid",
    "reference_number": "ABC123",
    "status": "submitted"
  },
  "customer": {
    "first_name": "John",
    "last_name": "Doe",
    "email": "john@example.com",
    "phone": "+1234567890"
  },
  "measurements": {
    "room_name": "Kitchen",
    "total_linear_ft": 25.5,
    "total_sq_ft": 150.0,
    "wall_count": 4,
    "window_count": 2,
    "door_count": 1,
    "lower_cabinet_count": 8,
    "upper_cabinet_count": 6,
    "lower_cabinets": [
      {
        "id": "lower_1",
        "width_ft": 2.5,
        "height_ft": 2.87,
        "depth_ft": 2.0,
        "width_inches": 30,
        "height_inches": 34.5,
        "depth_inches": 24
      }
    ],
    "upper_cabinets": [
      {
        "id": "upper_1",
        "width_ft": 2.5,
        "height_ft": 2.5,
        "depth_ft": 1.0,
        "width_inches": 30,
        "height_inches": 30,
        "depth_inches": 12
      }
    ],
    "walls": [...],
    "appliances": [...],
    "usdz_file_url": "https://...",
    "glb_file_url": "https://...",
    "preview_image_url": "https://..."
  },
  "selections": {
    "cabinet_model": {
      "category_name": "Cabinet Model",
      "product": "Shaker Premium",
      "variant": null,
      "price": 125.00,
      "pricing_unit": "per_cabinet",
      "quantity": 12,
      "notes": null
    },
    "cabinet_color": null,
    "cabinet_finish": null,
    "countertop": {
      "category_name": "Countertop",
      "product": "Granite Black Galaxy",
      "variant": null,
      "price": 85.00,
      "pricing_unit": "per_sq_ft",
      "quantity": 1,
      "notes": null
    },
    "countertop_edge": {
      "category_name": "Countertop Edge",
      "product": "Bullnose",
      "variant": null,
      "price": 8.00,
      "pricing_unit": "per_linear_ft",
      "quantity": 1,
      "notes": null
    },
    "hardware": {
      "category_name": "Hardware",
      "product": "Brushed Nickel Pulls",
      "variant": null,
      "price": 12.50,
      "pricing_unit": "per_piece",
      "quantity": 24,
      "notes": null
    },
    "backsplash": {
      "category_name": "Backsplash",
      "product": "Subway Tile White",
      "variant": null,
      "price": 12.50,
      "pricing_unit": "per_sq_ft",
      "quantity": 1,
      "notes": null
    },
    "sink": {
      "category_name": "Sink",
      "product": "Undermount Single Bowl",
      "variant": null,
      "price": 350.00,
      "pricing_unit": "per_piece",
      "quantity": 1,
      "notes": null
    },
    "faucet": {
      "category_name": "Faucet",
      "product": "Delta Single Handle",
      "variant": "Chrome",
      "price": 225.00,
      "pricing_unit": "per_piece",
      "quantity": 1,
      "notes": null
    },
    "cabinet_lighting": {
      "category_name": "Cabinet Lighting",
      "product": "LED Under Cabinet Strips",
      "variant": null,
      "price": 45.00,
      "pricing_unit": "per_linear_ft",
      "quantity": 1,
      "notes": null
    },
    "crown_molding": null,
    "toe_kick": null,
    "soft_close_hinges": {
      "category_name": "Soft-Close Hinges",
      "product": "Premium Soft-Close",
      "variant": null,
      "price": 8.00,
      "pricing_unit": "per_cabinet",
      "quantity": 1,
      "notes": null
    },
    "pull_out_organizers": {
      "category_name": "Pull-out Organizers",
      "product": "Spice Rack Pull-out",
      "variant": null,
      "price": 125.00,
      "pricing_unit": "per_piece",
      "quantity": 2,
      "notes": null
    }
  },
  "showroom": {
    "id": "uuid",
    "name": "Your Showroom",
    "code": "DEMO01"
  }
}`}
                  </pre>
                )}
              </div>
            </>
          ) : (
            <div className="py-6 text-center">
              <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-blue-100 mb-4">
                <Sparkles className="h-6 w-6 text-blue-600" />
              </div>
              <h3 className="text-lg font-medium mb-2">Upgrade to Pro</h3>
              <p className="text-gray-500 mb-4 max-w-md mx-auto">
                {getUpgradeReason('webhookAccess')}
              </p>
              <Link href="/showroom/billing">
                <Button>
                  Upgrade Plan
                </Button>
              </Link>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Quote Email Webhook */}
      <Card className={!canUseWebhooks ? 'border-gray-200 bg-gray-50/50' : ''}>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Webhook className="h-5 w-5" />
            Quote Email Webhook
            {!canUseWebhooks && (
              <Badge variant="secondary" className="ml-2 gap-1">
                <Lock className="h-3 w-3" />
                Pro
              </Badge>
            )}
          </CardTitle>
          <CardDescription>
            Send quote emails when you click &quot;Send Email to Customer&quot;. We&apos;ll send a POST request
            with the email content, customer details, and quote summary to your n8n workflow for email delivery.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {canUseWebhooks ? (
            <>
              <div className="space-y-2">
                <Label htmlFor="quote-webhook-url">Quote Email Webhook URL</Label>
                <div className="flex gap-2">
                  <Input
                    id="quote-webhook-url"
                    type="url"
                    placeholder="https://your-n8n.com/webhook/send-quote-email"
                    value={quoteWebhookUrl}
                    onChange={(e) => {
                      setQuoteWebhookUrl(e.target.value)
                      setQuoteWebhookError(null)
                    }}
                    className="flex-1"
                  />
                  <Button
                    onClick={saveQuoteWebhookUrl}
                    disabled={quoteWebhookSaving}
                  >
                    {quoteWebhookSaving ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      'Save'
                    )}
                  </Button>
                </div>
                {quoteWebhookError && (
                  <div className="flex items-center gap-2 text-sm text-red-600">
                    <AlertCircle className="h-4 w-4" />
                    {quoteWebhookError}
                  </div>
                )}
                {quoteWebhookSuccess && (
                  <div className="flex items-center gap-2 text-sm text-green-600">
                    <CheckCircle className="h-4 w-4" />
                    Quote webhook URL saved successfully
                  </div>
                )}
              </div>

              <Separator />

              <div className="space-y-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowQuoteWebhookExample(!showQuoteWebhookExample)}
                  className="w-full justify-between"
                >
                  <span className="text-gray-600">View Webhook Payload Example</span>
                  {showQuoteWebhookExample ? (
                    <ChevronUp className="h-4 w-4" />
                  ) : (
                    <ChevronDown className="h-4 w-4" />
                  )}
                </Button>
                {showQuoteWebhookExample && (
                  <pre className="bg-gray-100 p-4 rounded-lg text-xs overflow-x-auto max-h-96">
{`{
  "action": "send_email",
  "to": "customer@example.com",
  "subject": "Your Kitchen Quote - Elite Cabinets",
  "body_html": "<html>...</html>",
  "body_text": "plain text version",
  "customer_name": "John Doe",
  "reference_number": "REF-12345",
  "grand_total": "$15,000",
  "quote_summary": {
    "cabinets": "$10,000",
    "countertops": "$4,000",
    "backsplash": "$1,000",
    "total": "$15,000"
  },
  "showroom_name": "Elite Cabinets"
}`}
                  </pre>
                )}
              </div>
            </>
          ) : (
            <div className="py-6 text-center">
              <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-blue-100 mb-4">
                <Sparkles className="h-6 w-6 text-blue-600" />
              </div>
              <h3 className="text-lg font-medium mb-2">Upgrade to Pro</h3>
              <p className="text-gray-500 mb-4 max-w-md mx-auto">
                {getUpgradeReason('webhookAccess')}
              </p>
              <Link href="/showroom/billing">
                <Button>
                  Upgrade Plan
                </Button>
              </Link>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Danger Zone */}
      <Card className="border-red-200">
        <CardHeader>
          <CardTitle className="text-red-600">Danger Zone</CardTitle>
          <CardDescription>Irreversible actions for your showroom</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium">Delete all products</p>
              <p className="text-sm text-gray-500">
                Remove all products from your showroom. This cannot be undone.
              </p>
            </div>
            <Button variant="destructive" size="sm">
              Delete Products
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
