'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Separator } from '@/components/ui/separator'
import { Switch } from '@/components/ui/switch'
import {
  Loader2,
  Save,
  Phone,
  Info,
  Copy,
  Check,
  Eye,
  EyeOff,
  ChevronDown,
  ChevronUp,
} from 'lucide-react'
import { toast } from 'sonner'

const SETTINGS_KEYS = [
  'voice_agent_globally_enabled',
  'vapi_api_key',
  'vapi_phone_number_id',
  'twilio_account_sid',
  'twilio_auth_token',
  'twilio_phone_number',
  'google_maps_api_key',
  'voice_agent_default_sms_template',
  'voice_agent_default_system_prompt',
] as const

type SettingsKey = (typeof SETTINGS_KEYS)[number]

const DEFAULT_SMS_TEMPLATE = `Hi {{customer_name}}, this is {{showroom_name}}! Thanks for your recent visit. We'd love to help you with your project. Can we give you a quick call to discuss next steps?`

const DEFAULT_SYSTEM_PROMPT = `You are a friendly follow-up assistant calling on behalf of {{showroom_name}}.

Your goal:
- Thank the customer for visiting the showroom
- Ask about their project timeline
- Gauge their interest level
- If interested, offer to schedule a follow-up visit or send a scheduling link
- If not interested, thank them politely and end the call

Guidelines:
- Be warm and conversational
- Keep it brief (2-3 minutes max)
- Never discuss pricing
- Use {{customer_name}} naturally
- If they mention distance concerns, acknowledge and offer virtual consultation`

const TEMPLATE_VARIABLES = [
  { name: '{{customer_name}}', desc: 'Customer first name' },
  { name: '{{customer_full_name}}', desc: 'Customer full name' },
  { name: '{{showroom_name}}', desc: 'Showroom business name' },
  { name: '{{showroom_phone}}', desc: 'Showroom phone number' },
  { name: '{{scheduling_link}}', desc: 'Booking/scheduling URL' },
  { name: '{{distance_miles}}', desc: 'Distance in miles' },
  { name: '{{drive_time}}', desc: 'Estimated drive time' },
  { name: '{{project_type}}', desc: 'Type of project (kitchen, bath, etc.)' },
]

export default function AdminVoiceAgentPage() {
  const supabase = createClient()

  // Global toggle
  const [globalEnabled, setGlobalEnabled] = useState(false)
  const [globalToggleLoading, setGlobalToggleLoading] = useState(false)

  // API credentials
  const [vapiApiKey, setVapiApiKey] = useState('')
  const [vapiPhoneNumberId, setVapiPhoneNumberId] = useState('')
  const [twilioAccountSid, setTwilioAccountSid] = useState('')
  const [twilioAuthToken, setTwilioAuthToken] = useState('')
  const [twilioPhoneNumber, setTwilioPhoneNumber] = useState('')
  const [googleMapsApiKey, setGoogleMapsApiKey] = useState('')

  // Visibility toggles for masked fields
  const [showVapiKey, setShowVapiKey] = useState(false)
  const [showTwilioSid, setShowTwilioSid] = useState(false)
  const [showTwilioToken, setShowTwilioToken] = useState(false)
  const [showGoogleKey, setShowGoogleKey] = useState(false)

  // Templates
  const [defaultSmsTemplate, setDefaultSmsTemplate] = useState('')
  const [defaultSystemPrompt, setDefaultSystemPrompt] = useState('')

  // Save states
  const [savingField, setSavingField] = useState<string | null>(null)

  // Page loading
  const [loading, setLoading] = useState(true)

  // Variable hints expanded
  const [showVariables, setShowVariables] = useState(false)

  // Webhook URL copied
  const [copied, setCopied] = useState(false)

  // Load all settings
  useEffect(() => {
    async function loadSettings() {
      setLoading(true)
      try {
        const { data, error } = await supabase
          .from('platform_settings')
          .select('key, value')
          .in('key', [...SETTINGS_KEYS])

        if (error) throw error

        const settingsMap: Record<string, string> = {}
        if (data) {
          for (const row of data) {
            settingsMap[row.key] = row.value ?? ''
          }
        }

        setGlobalEnabled(settingsMap.voice_agent_globally_enabled === 'true')
        setVapiApiKey(settingsMap.vapi_api_key || '')
        setVapiPhoneNumberId(settingsMap.vapi_phone_number_id || '')
        setTwilioAccountSid(settingsMap.twilio_account_sid || '')
        setTwilioAuthToken(settingsMap.twilio_auth_token || '')
        setTwilioPhoneNumber(settingsMap.twilio_phone_number || '')
        setGoogleMapsApiKey(settingsMap.google_maps_api_key || '')
        setDefaultSmsTemplate(settingsMap.voice_agent_default_sms_template || '')
        setDefaultSystemPrompt(settingsMap.voice_agent_default_system_prompt || '')
      } catch (error) {
        console.error('Error loading voice agent settings:', error)
        toast.error('Failed to load settings')
      } finally {
        setLoading(false)
      }
    }

    loadSettings()
  }, [supabase])

  // Save a single setting
  const saveSetting = useCallback(
    async (key: SettingsKey, value: string, fieldLabel: string) => {
      setSavingField(key)
      try {
        const { error } = await supabase
          .from('platform_settings')
          .upsert(
            { key, value, updated_at: new Date().toISOString() },
            { onConflict: 'key' }
          )

        if (error) throw error
        toast.success(`${fieldLabel} saved successfully`)
      } catch (error) {
        console.error(`Error saving ${key}:`, error)
        toast.error(`Failed to save ${fieldLabel}`)
      } finally {
        setSavingField(null)
      }
    },
    [supabase]
  )

  // Toggle global enabled
  const handleGlobalToggle = useCallback(
    async (checked: boolean) => {
      setGlobalToggleLoading(true)
      setGlobalEnabled(checked)
      try {
        const { error } = await supabase
          .from('platform_settings')
          .upsert(
            {
              key: 'voice_agent_globally_enabled',
              value: String(checked),
              updated_at: new Date().toISOString(),
            },
            { onConflict: 'key' }
          )

        if (error) throw error
        toast.success(
          checked ? 'Voice Agent enabled globally' : 'Voice Agent disabled globally'
        )
      } catch (error) {
        console.error('Error toggling voice agent:', error)
        setGlobalEnabled(!checked)
        toast.error('Failed to update global toggle')
      } finally {
        setGlobalToggleLoading(false)
      }
    },
    [supabase]
  )

  // Copy webhook URL
  const webhookUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/voice-agent-webhook`
  const handleCopyWebhook = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(webhookUrl)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
      toast.success('Webhook URL copied')
    } catch {
      toast.error('Failed to copy')
    }
  }, [webhookUrl])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Voice Agent</h1>
        <p className="text-gray-500">
          Configure the AI voice agent for automated customer follow-up calls
        </p>
      </div>

      {/* Global Toggle */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-green-100 rounded-lg">
                <Phone className="h-6 w-6 text-green-600" />
              </div>
              <div>
                <CardTitle>Voice Agent Global Toggle</CardTitle>
                <CardDescription>
                  Enable or disable the voice agent across the entire platform. When
                  disabled, no showrooms can use the voice agent.
                </CardDescription>
              </div>
            </div>
            <Switch
              checked={globalEnabled}
              onCheckedChange={handleGlobalToggle}
              disabled={globalToggleLoading}
            />
          </div>
        </CardHeader>
      </Card>

      {/* API Credentials */}
      <Card>
        <CardHeader>
          <CardTitle>API Credentials</CardTitle>
          <CardDescription>
            API keys and credentials for third-party integrations. These are stored
            securely and never exposed to the client.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <CredentialRow
            label="Vapi API Key"
            value={vapiApiKey}
            onChange={setVapiApiKey}
            onSave={() => saveSetting('vapi_api_key', vapiApiKey, 'Vapi API Key')}
            saving={savingField === 'vapi_api_key'}
            masked
            visible={showVapiKey}
            onToggleVisibility={() => setShowVapiKey(!showVapiKey)}
          />

          <Separator />

          <CredentialRow
            label="Vapi Phone Number ID"
            value={vapiPhoneNumberId}
            onChange={setVapiPhoneNumberId}
            onSave={() =>
              saveSetting(
                'vapi_phone_number_id',
                vapiPhoneNumberId,
                'Vapi Phone Number ID'
              )
            }
            saving={savingField === 'vapi_phone_number_id'}
          />

          <Separator />

          <CredentialRow
            label="Twilio Account SID"
            value={twilioAccountSid}
            onChange={setTwilioAccountSid}
            onSave={() =>
              saveSetting('twilio_account_sid', twilioAccountSid, 'Twilio Account SID')
            }
            saving={savingField === 'twilio_account_sid'}
            masked
            visible={showTwilioSid}
            onToggleVisibility={() => setShowTwilioSid(!showTwilioSid)}
          />

          <Separator />

          <CredentialRow
            label="Twilio Auth Token"
            value={twilioAuthToken}
            onChange={setTwilioAuthToken}
            onSave={() =>
              saveSetting('twilio_auth_token', twilioAuthToken, 'Twilio Auth Token')
            }
            saving={savingField === 'twilio_auth_token'}
            masked
            visible={showTwilioToken}
            onToggleVisibility={() => setShowTwilioToken(!showTwilioToken)}
          />

          <Separator />

          <CredentialRow
            label="Twilio Phone Number"
            value={twilioPhoneNumber}
            onChange={setTwilioPhoneNumber}
            onSave={() =>
              saveSetting(
                'twilio_phone_number',
                twilioPhoneNumber,
                'Twilio Phone Number'
              )
            }
            saving={savingField === 'twilio_phone_number'}
            placeholder="+1234567890 (E.164 format)"
          />

          <Separator />

          <CredentialRow
            label="Google Maps API Key"
            value={googleMapsApiKey}
            onChange={setGoogleMapsApiKey}
            onSave={() =>
              saveSetting(
                'google_maps_api_key',
                googleMapsApiKey,
                'Google Maps API Key'
              )
            }
            saving={savingField === 'google_maps_api_key'}
            masked
            visible={showGoogleKey}
            onToggleVisibility={() => setShowGoogleKey(!showGoogleKey)}
          />
        </CardContent>
      </Card>

      {/* Default Templates */}
      <Card>
        <CardHeader>
          <CardTitle>Default Templates</CardTitle>
          <CardDescription>
            Master default templates used when a showroom has not configured its own.
            Showrooms can override these per distance/customer-type combination.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Variable hints */}
          <button
            onClick={() => setShowVariables(!showVariables)}
            className="flex items-center gap-2 text-sm text-blue-600 hover:text-blue-700 font-medium"
          >
            <Info className="h-4 w-4" />
            Available Template Variables
            {showVariables ? (
              <ChevronUp className="h-4 w-4" />
            ) : (
              <ChevronDown className="h-4 w-4" />
            )}
          </button>

          {showVariables && (
            <div className="p-3 bg-blue-50 rounded-lg">
              <ul className="space-y-1">
                {TEMPLATE_VARIABLES.map((v) => (
                  <li key={v.name} className="text-sm text-blue-700">
                    <code className="bg-blue-100 px-1 rounded font-mono text-xs">
                      {v.name}
                    </code>{' '}
                    &mdash; {v.desc}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <Separator />

          {/* SMS Template */}
          <div className="space-y-2">
            <Label className="text-base font-semibold">Default SMS Template</Label>
            <Textarea
              value={defaultSmsTemplate}
              onChange={(e) => setDefaultSmsTemplate(e.target.value)}
              placeholder={DEFAULT_SMS_TEMPLATE}
              className="min-h-[120px] font-mono text-sm"
            />
            <div className="flex justify-end">
              <Button
                onClick={() =>
                  saveSetting(
                    'voice_agent_default_sms_template',
                    defaultSmsTemplate,
                    'Default SMS Template'
                  )
                }
                disabled={savingField === 'voice_agent_default_sms_template'}
                size="sm"
                className="gap-2"
              >
                {savingField === 'voice_agent_default_sms_template' ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Save className="h-4 w-4" />
                )}
                Save SMS Template
              </Button>
            </div>
          </div>

          <Separator />

          {/* System Prompt */}
          <div className="space-y-2">
            <Label className="text-base font-semibold">Default System Prompt</Label>
            <Textarea
              value={defaultSystemPrompt}
              onChange={(e) => setDefaultSystemPrompt(e.target.value)}
              placeholder={DEFAULT_SYSTEM_PROMPT}
              className="min-h-[300px] font-mono text-sm"
            />
            <div className="flex justify-end">
              <Button
                onClick={() =>
                  saveSetting(
                    'voice_agent_default_system_prompt',
                    defaultSystemPrompt,
                    'Default System Prompt'
                  )
                }
                disabled={savingField === 'voice_agent_default_system_prompt'}
                size="sm"
                className="gap-2"
              >
                {savingField === 'voice_agent_default_system_prompt' ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Save className="h-4 w-4" />
                )}
                Save System Prompt
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Webhook URL */}
      <Card>
        <CardHeader>
          <CardTitle>Webhook URL</CardTitle>
          <CardDescription>
            Configure this URL in your Vapi dashboard to receive call status updates.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center gap-2">
            <Input
              value={webhookUrl}
              readOnly
              className="font-mono text-sm bg-gray-50"
            />
            <Button
              variant="outline"
              size="icon"
              onClick={handleCopyWebhook}
              className="flex-shrink-0"
            >
              {copied ? (
                <Check className="h-4 w-4 text-green-600" />
              ) : (
                <Copy className="h-4 w-4" />
              )}
            </Button>
          </div>
          <p className="text-sm text-gray-500">
            This is a read-only URL. Paste it into your Vapi assistant&apos;s webhook
            configuration to enable call event processing.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// CredentialRow — reusable row for API credential fields
// ---------------------------------------------------------------------------
function CredentialRow({
  label,
  value,
  onChange,
  onSave,
  saving,
  masked,
  visible,
  onToggleVisibility,
  placeholder,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  onSave: () => void
  saving: boolean
  masked?: boolean
  visible?: boolean
  onToggleVisibility?: () => void
  placeholder?: string
}) {
  const inputType = masked && !visible ? 'password' : 'text'

  return (
    <div className="space-y-2">
      <Label className="font-medium">{label}</Label>
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <Input
            type={inputType}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder ?? `Enter ${label.toLowerCase()}...`}
            className="pr-10 font-mono text-sm"
          />
          {masked && onToggleVisibility && (
            <button
              type="button"
              onClick={onToggleVisibility}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              {visible ? (
                <EyeOff className="h-4 w-4" />
              ) : (
                <Eye className="h-4 w-4" />
              )}
            </button>
          )}
        </div>
        <Button
          onClick={onSave}
          disabled={saving}
          size="sm"
          className="gap-2 flex-shrink-0"
        >
          {saving ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Save className="h-4 w-4" />
          )}
          Save
        </Button>
      </div>
    </div>
  )
}
