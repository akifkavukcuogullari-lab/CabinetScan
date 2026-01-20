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
import { Webhook, CheckCircle, AlertCircle, Loader2, Lock, Sparkles, ChevronDown, ChevronUp, Edit2, RefreshCw, Save, X, Mail, Send, Bot, Upload, Trash2 } from 'lucide-react'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
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

  // Email notification state
  const [notificationEmails, setNotificationEmails] = useState('')
  const [notificationSaving, setNotificationSaving] = useState(false)
  const [notificationError, setNotificationError] = useState<string | null>(null)
  const [notificationSuccess, setNotificationSuccess] = useState(false)
  const [sendingTestEmail, setSendingTestEmail] = useState(false)
  const [testEmailError, setTestEmailError] = useState<string | null>(null)
  const [testEmailSuccess, setTestEmailSuccess] = useState(false)

  // AI Designer Agent state
  const [aiChatbotEnabled, setAiChatbotEnabled] = useState(false)
  const [aiAssistantName, setAiAssistantName] = useState('Design Assistant')
  const [aiAssistantAvatarUrl, setAiAssistantAvatarUrl] = useState<string | null>(null)
  const [aiSaving, setAiSaving] = useState(false)
  const [aiSuccess, setAiSuccess] = useState(false)
  const [aiError, setAiError] = useState<string | null>(null)
  const [avatarUploading, setAvatarUploading] = useState(false)

  // Check if AI Designer Agent feature is available (Business+ plans)
  const canUseAiAgent = canUseFeature('aiDesignerAgent')

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
        setNotificationEmails(showroomData.notification_emails || '')
        // Initialize edit form
        setShowroomName(showroomData.name || '')
        setShowroomCode(showroomData.showroom_code || '')
        setShowroomEmail(showroomData.email || '')
        setShowroomPhone(showroomData.phone || '')
        // AI settings
        setAiChatbotEnabled(showroomData.ai_chatbot_enabled || false)
        setAiAssistantName(showroomData.ai_assistant_name || 'Design Assistant')
        setAiAssistantAvatarUrl(showroomData.ai_assistant_avatar_url || null)
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

  const formatPhoneNumber = (phone: string): string => {
    // Remove all non-numeric characters
    const cleaned = phone.replace(/[^0-9]/g, '')

    // If starts with 1, keep it
    if (cleaned.startsWith('1')) {
      return '+' + cleaned
    }

    // Otherwise, add +1 prefix
    return cleaned ? '+1' + cleaned : ''
  }

  const validateEmail = (email: string): boolean => {
    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailPattern.test(email)
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

    if (!validateEmail(showroomEmail.trim())) {
      setInfoError('Please enter a valid email address')
      return
    }

    if (!showroomPhone.trim()) {
      setInfoError('Phone number is required')
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

    // Format phone number
    const formattedPhone = formatPhoneNumber(showroomPhone)
    if (!formattedPhone || formattedPhone.length < 12) { // +1 + 10 digits minimum
      setInfoError('Please enter a valid phone number (minimum 10 digits)')
      return
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
        phone: formattedPhone,
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
        phone: formattedPhone,
      })
      setShowroomCode(upperCode) // Update to uppercase
      setShowroomPhone(formattedPhone) // Update with formatted phone
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

  const validateNotificationEmails = (emails: string): { valid: boolean; error?: string } => {
    if (!emails.trim()) {
      return { valid: true } // Empty is valid
    }

    const list = emails.split(',').map(e => e.trim()).filter(e => e)

    if (list.length > 5) {
      return { valid: false, error: 'Maximum 5 email addresses allowed' }
    }

    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    for (const email of list) {
      if (!emailPattern.test(email)) {
        return { valid: false, error: `Invalid email address: ${email}` }
      }
    }

    return { valid: true }
  }

  const saveNotificationEmails = async () => {
    if (!showroomId) return

    // Validate emails
    const validation = validateNotificationEmails(notificationEmails)
    if (!validation.valid) {
      setNotificationError(validation.error || 'Invalid email addresses')
      return
    }

    // Clean up and deduplicate emails
    const cleanedEmails = notificationEmails
      .split(',')
      .map(e => e.trim())
      .filter((e, index, arr) => e && arr.indexOf(e) === index) // Remove duplicates
      .join(', ')

    setNotificationSaving(true)
    setNotificationError(null)
    setNotificationSuccess(false)

    const { error } = await supabase
      .from('showrooms')
      .update({ notification_emails: cleanedEmails || null })
      .eq('id', showroomId)

    setNotificationSaving(false)

    if (error) {
      setNotificationError('Failed to save notification emails')
    } else {
      setNotificationEmails(cleanedEmails)
      setShowroom({ ...showroom, notification_emails: cleanedEmails })
      setNotificationSuccess(true)
      setTimeout(() => setNotificationSuccess(false), 3000)
    }
  }

  const sendTestNotification = async () => {
    if (!showroomId) return

    // Check if emails are configured
    const emails = notificationEmails.trim()
    if (!emails) {
      setTestEmailError('Please configure and save notification emails first')
      return
    }

    setSendingTestEmail(true)
    setTestEmailError(null)
    setTestEmailSuccess(false)

    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        setTestEmailError('Not authenticated')
        setSendingTestEmail(false)
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-test-notification`,
        {
          method: 'POST',
          headers: {
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
            'Authorization': `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ showroom_id: showroomId }),
        }
      )

      const result = await response.json()

      if (!response.ok || !result.success) {
        setTestEmailError(result.error || result.message || 'Failed to send test notification')
      } else {
        setTestEmailSuccess(true)
        setTimeout(() => setTestEmailSuccess(false), 5000)
      }
    } catch (error) {
      setTestEmailError('Failed to send test notification')
      console.error('Test notification error:', error)
    }

    setSendingTestEmail(false)
  }

  const toggleAiChatbot = async (enabled: boolean) => {
    if (!showroomId) return

    setAiSaving(true)
    setAiError(null)
    setAiSuccess(false)

    const { error } = await supabase
      .from('showrooms')
      .update({ ai_chatbot_enabled: enabled })
      .eq('id', showroomId)

    setAiSaving(false)

    if (error) {
      setAiError('Failed to update AI chatbot setting')
    } else {
      setAiChatbotEnabled(enabled)
      setShowroom({ ...showroom, ai_chatbot_enabled: enabled })
      setAiSuccess(true)
      setTimeout(() => setAiSuccess(false), 3000)
    }
  }

  const saveAiAssistantName = async () => {
    if (!showroomId) return

    const trimmedName = aiAssistantName.trim()
    if (!trimmedName) {
      setAiError('Assistant name cannot be empty')
      return
    }

    if (trimmedName.length > 30) {
      setAiError('Assistant name must be 30 characters or less')
      return
    }

    setAiSaving(true)
    setAiError(null)
    setAiSuccess(false)

    const { error } = await supabase
      .from('showrooms')
      .update({ ai_assistant_name: trimmedName })
      .eq('id', showroomId)

    setAiSaving(false)

    if (error) {
      setAiError('Failed to update assistant name')
    } else {
      setAiAssistantName(trimmedName)
      setShowroom({ ...showroom, ai_assistant_name: trimmedName })
      setAiSuccess(true)
      setTimeout(() => setAiSuccess(false), 3000)
    }
  }

  const handleAvatarUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file || !showroomId) return

    // Validate file type
    if (!file.type.startsWith('image/')) {
      setAiError('Please select an image file')
      return
    }

    // Validate file size (max 2MB)
    if (file.size > 2 * 1024 * 1024) {
      setAiError('Image must be less than 2MB')
      return
    }

    setAvatarUploading(true)
    setAiError(null)

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `ai-avatar-${showroomId}-${Date.now()}.${fileExt}`
      const filePath = `ai-avatars/${fileName}`

      const { error: uploadError } = await supabase.storage
        .from('logos')
        .upload(filePath, file, { upsert: true })

      if (uploadError) throw uploadError

      const { data: { publicUrl } } = supabase.storage
        .from('logos')
        .getPublicUrl(filePath)

      // Save to database
      const { error: dbError } = await supabase
        .from('showrooms')
        .update({ ai_assistant_avatar_url: publicUrl })
        .eq('id', showroomId)

      if (dbError) throw dbError

      setAiAssistantAvatarUrl(publicUrl)
      setShowroom({ ...showroom, ai_assistant_avatar_url: publicUrl })
      setAiSuccess(true)
      setTimeout(() => setAiSuccess(false), 3000)
    } catch (error) {
      console.error('Error uploading avatar:', error)
      setAiError('Failed to upload avatar')
    } finally {
      setAvatarUploading(false)
    }
  }

  const removeAvatar = async () => {
    if (!showroomId) return

    setAiSaving(true)
    setAiError(null)

    const { error } = await supabase
      .from('showrooms')
      .update({ ai_assistant_avatar_url: null })
      .eq('id', showroomId)

    setAiSaving(false)

    if (error) {
      setAiError('Failed to remove avatar')
    } else {
      setAiAssistantAvatarUrl(null)
      setShowroom({ ...showroom, ai_assistant_avatar_url: null })
      setAiSuccess(true)
      setTimeout(() => setAiSuccess(false), 3000)
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
                onClick={() => {
                  // Ensure fields are populated with current data
                  setShowroomName(showroom?.name || '')
                  setShowroomCode(showroom?.showroom_code || '')
                  setShowroomEmail(showroom?.email || '')
                  setShowroomPhone(showroom?.phone || '')
                  setInfoError(null)
                  setIsEditingInfo(true)
                }}
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
                    <div className="flex">
                      <div className="flex items-center px-3 bg-gray-100 border border-r-0 border-gray-300 rounded-l-md text-gray-600 font-medium">
                        +1
                      </div>
                      <Input
                        id="showroom-phone"
                        type="tel"
                        value={showroomPhone.replace(/^\+1/, '')}
                        onChange={(e) => {
                          const value = e.target.value.replace(/[^0-9]/g, '')
                          setShowroomPhone('+1' + value)
                          setInfoError(null)
                        }}
                        placeholder="5551234567"
                        className="rounded-l-none"
                      />
                    </div>
                    <p className="text-xs text-gray-500 mt-1">
                      Enter 10-digit phone number
                    </p>
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

      {/* Email Notifications */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Mail className="h-5 w-5" />
            Email Notifications
          </CardTitle>
          <CardDescription>
            Configure email addresses to receive notifications when new projects are submitted.
            You can add up to 5 email addresses (comma-separated).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="notification-emails">Notification Email Addresses</Label>
            <Input
              id="notification-emails"
              type="text"
              placeholder="email1@example.com, email2@example.com"
              value={notificationEmails}
              onChange={(e) => {
                setNotificationEmails(e.target.value)
                setNotificationError(null)
              }}
              className="flex-1"
            />
            <p className="text-xs text-gray-500">
              Separate multiple email addresses with commas. Maximum 5 addresses.
            </p>
          </div>

          {notificationError && (
            <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">
              <AlertCircle className="h-4 w-4 flex-shrink-0" />
              {notificationError}
            </div>
          )}

          {notificationSuccess && (
            <div className="flex items-center gap-2 text-sm text-green-600 bg-green-50 p-3 rounded-lg">
              <CheckCircle className="h-4 w-4 flex-shrink-0" />
              Notification emails saved successfully
            </div>
          )}

          {testEmailError && (
            <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">
              <AlertCircle className="h-4 w-4 flex-shrink-0" />
              {testEmailError}
            </div>
          )}

          {testEmailSuccess && (
            <div className="flex items-center gap-2 text-sm text-green-600 bg-green-50 p-3 rounded-lg">
              <CheckCircle className="h-4 w-4 flex-shrink-0" />
              Test notification sent successfully! Check your inbox.
            </div>
          )}

          <div className="flex gap-2">
            <Button
              onClick={saveNotificationEmails}
              disabled={notificationSaving}
              className="flex-1"
            >
              {notificationSaving ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Saving...
                </>
              ) : (
                <>
                  <Save className="h-4 w-4 mr-2" />
                  Save Emails
                </>
              )}
            </Button>
            <Button
              variant="outline"
              onClick={sendTestNotification}
              disabled={sendingTestEmail || !notificationEmails.trim()}
              className="flex-1"
            >
              {sendingTestEmail ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Sending...
                </>
              ) : (
                <>
                  <Send className="h-4 w-4 mr-2" />
                  Send Test Notification
                </>
              )}
            </Button>
          </div>

          <Separator />

          <div className="bg-blue-50 p-4 rounded-lg">
            <h4 className="text-sm font-medium text-blue-900 mb-2">What&apos;s included in notifications?</h4>
            <ul className="text-sm text-blue-800 space-y-1">
              <li>• Customer name and contact information</li>
              <li>• Project reference number</li>
              <li>• Submission date and time</li>
              <li>• Direct link to view project details in dashboard</li>
            </ul>
            <p className="text-xs text-blue-700 mt-3">
              Notifications are sent immediately when a customer submits a new project from the iOS app.
            </p>
          </div>
        </CardContent>
      </Card>

      {/* AI Designer Agent */}
      <Card className={!canUseAiAgent ? 'border-gray-200 bg-gray-50/50' : ''}>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Bot className="h-5 w-5" />
            AI Designer Agent
            {!canUseAiAgent && (
              <Badge variant="secondary" className="ml-2 gap-1">
                <Lock className="h-3 w-3" />
                Business
              </Badge>
            )}
          </CardTitle>
          <CardDescription>
            An AI chatbot that helps customers share their design preferences after submitting a project.
            The AI collects style preferences, timeline, and requirements to help your team prepare better quotes.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {canUseAiAgent ? (
            <>
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-purple-100 rounded-lg">
                    <Bot className="h-5 w-5 text-purple-600" />
                  </div>
                  <div>
                    <p className="font-medium">Enable for Customers</p>
                    <p className="text-sm text-gray-500">
                      Show &quot;Chat with {aiAssistantName}&quot; option after project submission
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  {aiSaving && (
                    <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
                  )}
                  <Switch
                    checked={aiChatbotEnabled}
                    onCheckedChange={toggleAiChatbot}
                    disabled={aiSaving}
                  />
                </div>
              </div>

              {aiError && (
                <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">
                  <AlertCircle className="h-4 w-4 flex-shrink-0" />
                  {aiError}
                </div>
              )}

              {aiSuccess && (
                <div className="flex items-center gap-2 text-sm text-green-600 bg-green-50 p-3 rounded-lg">
                  <CheckCircle className="h-4 w-4 flex-shrink-0" />
                  AI chatbot setting updated successfully
                </div>
              )}

              <Separator />

              {/* Assistant Identity */}
              <div className="space-y-4">
                <h4 className="text-sm font-medium flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-purple-600" />
                  Assistant Identity
                </h4>
                <div className="grid gap-6 md:grid-cols-2">
                  {/* Name */}
                  <div className="space-y-2">
                    <Label htmlFor="ai-assistant-name">Assistant Name</Label>
                    <p className="text-xs text-gray-500 mb-2">
                      This name will be shown to customers in the chat interface
                    </p>
                    <div className="flex gap-2">
                      <Input
                        id="ai-assistant-name"
                        value={aiAssistantName}
                        onChange={(e) => {
                          setAiAssistantName(e.target.value)
                          setAiError(null)
                        }}
                        placeholder="e.g., Sophie, Design Assistant"
                        maxLength={30}
                        className="max-w-xs"
                      />
                      <Button
                        onClick={saveAiAssistantName}
                        disabled={aiSaving || aiAssistantName === showroom?.ai_assistant_name}
                        size="sm"
                      >
                        {aiSaving ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <Save className="h-4 w-4" />
                        )}
                      </Button>
                    </div>
                  </div>

                  {/* Avatar */}
                  <div className="space-y-2">
                    <Label>Assistant Avatar</Label>
                    <p className="text-xs text-gray-500 mb-2">
                      Optional custom avatar for your AI assistant
                    </p>
                    <div className="flex items-center gap-4">
                      <Avatar className="h-16 w-16">
                        <AvatarImage src={aiAssistantAvatarUrl || undefined} alt={aiAssistantName} />
                        <AvatarFallback className="bg-purple-100 text-purple-700 text-lg">
                          {aiAssistantName.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2)}
                        </AvatarFallback>
                      </Avatar>
                      <div className="space-y-2">
                        <div className="flex gap-2">
                          <Button
                            variant="outline"
                            size="sm"
                            className="gap-2"
                            disabled={avatarUploading}
                            asChild
                          >
                            <label className="cursor-pointer">
                              {avatarUploading ? (
                                <Loader2 className="h-4 w-4 animate-spin" />
                              ) : (
                                <Upload className="h-4 w-4" />
                              )}
                              Upload
                              <input
                                type="file"
                                accept="image/*"
                                className="hidden"
                                onChange={handleAvatarUpload}
                              />
                            </label>
                          </Button>
                          {aiAssistantAvatarUrl && (
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={removeAvatar}
                              disabled={aiSaving}
                              className="gap-1 text-red-600 hover:text-red-700 hover:bg-red-50"
                            >
                              <Trash2 className="h-4 w-4" />
                              Remove
                            </Button>
                          )}
                        </div>
                        <p className="text-xs text-gray-500">
                          Square image, max 2MB
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div className="bg-purple-50 p-4 rounded-lg">
                <h4 className="text-sm font-medium text-purple-900 mb-2">How it works</h4>
                <ul className="text-sm text-purple-800 space-y-1">
                  <li>• Customer submits their project via the iOS app</li>
                  <li>• After submission, they see an option to chat with {aiAssistantName}</li>
                  <li>• The AI asks about design preferences, timeline, and requirements</li>
                  <li>• Conversation summary appears in project details on your dashboard</li>
                </ul>
              </div>
            </>
          ) : (
            <div className="py-6 text-center">
              <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-purple-100 mb-4">
                <Sparkles className="h-6 w-6 text-purple-600" />
              </div>
              <h3 className="text-lg font-medium mb-2">Upgrade to Business</h3>
              <p className="text-gray-500 mb-4 max-w-md mx-auto">
                {getUpgradeReason('aiDesignerAgent')}
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

      {/* Project Submission Webhook */}
      <Card className={!canUseWebhooks ? 'border-gray-200 bg-gray-50/50' : ''}>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Webhook className="h-5 w-5" />
            Project Submission Webhook
            {!canUseWebhooks && (
              <Badge variant="secondary" className="ml-2 gap-1">
                <Lock className="h-3 w-3" />
                Business
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
              <h3 className="text-lg font-medium mb-2">Upgrade to Business</h3>
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
                Business
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
              <h3 className="text-lg font-medium mb-2">Upgrade to Business</h3>
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
