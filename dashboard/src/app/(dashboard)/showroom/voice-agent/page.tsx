'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useSubscriptionContext } from '@/contexts/subscription-context'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Separator } from '@/components/ui/separator'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Loader2,
  Save,
  Phone,
  Info,
  Lock,
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  RotateCcw,
  Settings,
  MessageSquare,
  GitBranch,
  Activity,
  ArrowLeft,
} from 'lucide-react'
import { toast } from 'sonner'
import { VoiceAgentActivityList } from '@/components/voice-agent/VoiceAgentActivityList'
import type { VoiceAgentShowroomSettings, PostCallFlow } from '@/types/voice-agent'

// Default post-call flow
const DEFAULT_POST_CALL_FLOW: PostCallFlow = {
  nodes: [
    {
      id: 'outcome-1',
      type: 'outcome',
      data: { outcomes: ['no_answer', 'voicemail', 'line_busy'] },
      position: { x: 250, y: 0 },
    },
    {
      id: 'wait-1',
      type: 'wait',
      data: { hours: 2 },
      position: { x: 250, y: 120 },
    },
    {
      id: 'sms-1',
      type: 'sms',
      data: { template: 'follow_up' },
      position: { x: 250, y: 240 },
    },
    {
      id: 'wait-2',
      type: 'wait',
      data: { hours: 24 },
      position: { x: 250, y: 360 },
    },
    {
      id: 'retry-1',
      type: 'retry_call',
      data: { maxAttempts: 2 },
      position: { x: 250, y: 480 },
    },
    {
      id: 'stop-1',
      type: 'stop',
      data: { reason: 'Max retries reached' },
      position: { x: 250, y: 600 },
    },
  ],
  edges: [
    { source: 'outcome-1', target: 'wait-1' },
    { source: 'wait-1', target: 'sms-1' },
    { source: 'sms-1', target: 'wait-2' },
    { source: 'wait-2', target: 'retry-1' },
    { source: 'retry-1', target: 'stop-1' },
  ],
}

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

type TriggerMode = 'immediate' | 'delayed' | 'manual'

type PromptKey =
  | 'near_homeowner'
  | 'near_contractor'
  | 'far_homeowner'
  | 'far_contractor'

const PROMPT_SUBTABS: { key: PromptKey; label: string }[] = [
  { key: 'near_homeowner', label: 'Near / Homeowner' },
  { key: 'near_contractor', label: 'Near / Contractor' },
  { key: 'far_homeowner', label: 'Far / Homeowner' },
  { key: 'far_contractor', label: 'Far / Contractor' },
]

export default function ShowroomVoiceAgentPage() {
  const supabase = createClient()
  const { canUseFeature } = useSubscriptionContext()

  // Platform-level check
  const [platformEnabled, setPlatformEnabled] = useState<boolean | null>(null)
  const [platformLoading, setPlatformLoading] = useState(true)

  // Showroom ID
  const [showroomId, setShowroomId] = useState<string | null>(null)

  // Settings
  const [settings, setSettings] = useState<VoiceAgentShowroomSettings | null>(null)
  const [loading, setLoading] = useState(true)

  // General tab state
  const [enabled, setEnabled] = useState(false)
  const [triggerMode, setTriggerMode] = useState<TriggerMode>('manual')
  const [delayMinutes, setDelayMinutes] = useState(15)
  const [distanceThreshold, setDistanceThreshold] = useState(30)
  const [schedulingLink, setSchedulingLink] = useState('')
  const [agentName, setAgentName] = useState('')
  const [llmProvider, setLlmProvider] = useState('')
  const [llmModel, setLlmModel] = useState('')
  const [voiceProvider, setVoiceProvider] = useState('')
  const [voiceId, setVoiceId] = useState('')
  const [agentFirstMessage, setAgentFirstMessage] = useState('')
  const [generalSaving, setGeneralSaving] = useState(false)

  // Prompts tab state
  const [activePromptTab, setActivePromptTab] = useState<PromptKey>('near_homeowner')
  const [smsTemplates, setSmsTemplates] = useState<Record<PromptKey, string>>({
    near_homeowner: '',
    near_contractor: '',
    far_homeowner: '',
    far_contractor: '',
  })
  const [systemPrompts, setSystemPrompts] = useState<Record<PromptKey, string>>({
    near_homeowner: '',
    near_contractor: '',
    far_homeowner: '',
    far_contractor: '',
  })
  const [promptsSaving, setPromptsSaving] = useState(false)

  // Flow tab state
  const [postCallFlow, setPostCallFlow] = useState<PostCallFlow>(DEFAULT_POST_CALL_FLOW)
  const [flowSaving, setFlowSaving] = useState(false)

  // Variable hints
  const [showVariables, setShowVariables] = useState(false)

  // Master defaults for placeholders
  const [masterSmsDefault, setMasterSmsDefault] = useState('')
  const [masterPromptDefault, setMasterPromptDefault] = useState('')

  // Activity tab state
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [FlowDebuggerComponent, setFlowDebuggerComponent] = useState<React.ComponentType<any> | null>(null)

  // Lazy-load FlowDebugger (depends on React Flow)
  useEffect(() => {
    import('@/components/voice-agent/VoiceAgentFlowDebugger')
      .then((mod) => setFlowDebuggerComponent(() => mod.VoiceAgentFlowDebugger))
      .catch(() => console.warn('FlowDebugger not available'))
  }, [])

  // Check platform-level enabled
  useEffect(() => {
    async function checkPlatform() {
      setPlatformLoading(true)
      try {
        const { data, error } = await supabase
          .from('platform_settings')
          .select('value')
          .eq('key', 'voice_agent_globally_enabled')
          .limit(1)

        if (error) throw error
        setPlatformEnabled(data && data.length > 0 ? data[0].value === 'true' : false)

        // Also load master defaults for placeholders
        const { data: defaults } = await supabase
          .from('platform_settings')
          .select('key, value')
          .in('key', [
            'voice_agent_default_sms_template',
            'voice_agent_default_system_prompt',
          ])

        if (defaults) {
          for (const row of defaults) {
            if (row.key === 'voice_agent_default_sms_template') {
              setMasterSmsDefault(row.value || '')
            }
            if (row.key === 'voice_agent_default_system_prompt') {
              setMasterPromptDefault(row.value || '')
            }
          }
        }
      } catch (error) {
        console.error('Error checking platform settings:', error)
        setPlatformEnabled(false)
      } finally {
        setPlatformLoading(false)
      }
    }

    checkPlatform()
  }, [supabase])

  // Load showroom settings
  useEffect(() => {
    async function loadSettings() {
      setLoading(true)
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()
        if (!user) return

        const { data: showroomUser } = await supabase
          .from('showroom_users')
          .select('showroom_id')
          .eq('user_id', user.id)
          .single()

        if (!showroomUser) return
        setShowroomId(showroomUser.showroom_id)

        const { data, error } = await supabase
          .from('voice_agent_showroom_settings')
          .select('*')
          .eq('showroom_id', showroomUser.showroom_id)
          .limit(1)

        if (error) throw error

        if (data && data.length > 0) {
          const s = data[0] as VoiceAgentShowroomSettings
          setSettings(s)
          setEnabled(s.enabled)
          setTriggerMode(s.trigger_mode)
          setDelayMinutes(s.delay_minutes)
          setDistanceThreshold(s.distance_threshold_miles)
          setSchedulingLink(s.scheduling_link || '')
          setAgentName((s as any).agent_name || '')
          setLlmProvider((s as any).llm_provider || '')
          setLlmModel((s as any).llm_model || '')
          setVoiceProvider((s as any).voice_provider || '')
          setVoiceId((s as any).voice_id || '')
          setAgentFirstMessage((s as any).first_message || '')

          setSmsTemplates({
            near_homeowner: s.near_homeowner_sms_template || '',
            near_contractor: s.near_contractor_sms_template || '',
            far_homeowner: s.far_homeowner_sms_template || '',
            far_contractor: s.far_contractor_sms_template || '',
          })
          setSystemPrompts({
            near_homeowner: s.near_homeowner_system_prompt || '',
            near_contractor: s.near_contractor_system_prompt || '',
            far_homeowner: s.far_homeowner_system_prompt || '',
            far_contractor: s.far_contractor_system_prompt || '',
          })
          setPostCallFlow(s.post_call_flow || DEFAULT_POST_CALL_FLOW)
        }
      } catch (error) {
        console.error('Error loading voice agent settings:', error)
      } finally {
        setLoading(false)
      }
    }

    loadSettings()
  }, [supabase])

  // Save general settings
  const saveGeneral = useCallback(async () => {
    if (!showroomId) return
    setGeneralSaving(true)
    try {
      const { error } = await supabase
        .from('voice_agent_showroom_settings')
        .upsert(
          {
            showroom_id: showroomId,
            enabled,
            trigger_mode: triggerMode,
            delay_minutes: delayMinutes,
            distance_threshold_miles: distanceThreshold,
            scheduling_link: schedulingLink || null,
            agent_name: agentName || null,
            llm_provider: llmProvider || null,
            llm_model: llmModel || null,
            voice_provider: voiceProvider || null,
            voice_id: voiceId || null,
            first_message: agentFirstMessage || null,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'showroom_id' }
        )

      if (error) throw error
      toast.success('General settings saved')
    } catch (error) {
      console.error('Error saving general settings:', error)
      toast.error('Failed to save general settings')
    } finally {
      setGeneralSaving(false)
    }
  }, [supabase, showroomId, enabled, triggerMode, delayMinutes, distanceThreshold, schedulingLink])

  // Save prompts
  const savePrompts = useCallback(async () => {
    if (!showroomId) return
    setPromptsSaving(true)
    try {
      const { error } = await supabase
        .from('voice_agent_showroom_settings')
        .upsert(
          {
            showroom_id: showroomId,
            near_homeowner_sms_template: smsTemplates.near_homeowner || null,
            near_homeowner_system_prompt: systemPrompts.near_homeowner || null,
            near_contractor_sms_template: smsTemplates.near_contractor || null,
            near_contractor_system_prompt: systemPrompts.near_contractor || null,
            far_homeowner_sms_template: smsTemplates.far_homeowner || null,
            far_homeowner_system_prompt: systemPrompts.far_homeowner || null,
            far_contractor_sms_template: smsTemplates.far_contractor || null,
            far_contractor_system_prompt: systemPrompts.far_contractor || null,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'showroom_id' }
        )

      if (error) throw error
      toast.success('Prompts and templates saved')
    } catch (error) {
      console.error('Error saving prompts:', error)
      toast.error('Failed to save prompts')
    } finally {
      setPromptsSaving(false)
    }
  }, [supabase, showroomId, smsTemplates, systemPrompts])

  // Save post-call flow
  const saveFlow = useCallback(async () => {
    if (!showroomId) return
    setFlowSaving(true)
    try {
      const { error } = await supabase
        .from('voice_agent_showroom_settings')
        .upsert(
          {
            showroom_id: showroomId,
            post_call_flow: postCallFlow as unknown as Record<string, unknown>,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'showroom_id' }
        )

      if (error) throw error
      toast.success('Post-call flow saved')
    } catch (error) {
      console.error('Error saving flow:', error)
      toast.error('Failed to save flow')
    } finally {
      setFlowSaving(false)
    }
  }, [supabase, showroomId, postCallFlow])

  // Reset prompt to default (clear to null)
  const resetPrompt = useCallback(
    (key: PromptKey, field: 'sms' | 'prompt') => {
      if (field === 'sms') {
        setSmsTemplates((prev) => ({ ...prev, [key]: '' }))
      } else {
        setSystemPrompts((prev) => ({ ...prev, [key]: '' }))
      }
    },
    []
  )

  // Loading states
  if (platformLoading || loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    )
  }

  // Platform not enabled
  if (!platformEnabled) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">Voice Agent</h1>
          <p className="text-gray-500">Automated customer follow-up calls</p>
        </div>
        <Card>
          <CardContent className="py-12 text-center">
            <div className="flex flex-col items-center gap-3">
              <div className="p-3 bg-yellow-100 rounded-full">
                <AlertTriangle className="h-8 w-8 text-yellow-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900">
                Voice Agent is not available
              </h3>
              <p className="text-gray-500 max-w-md">
                The voice agent feature has not been enabled by the platform
                administrator. Please contact support if you believe this is an error.
              </p>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Feature gate (subscription)
  const canUseVoiceAgent = canUseFeature('voiceAgent' as keyof import('@/lib/subscription').PlanFeatures)
  if (!canUseVoiceAgent) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">Voice Agent</h1>
          <p className="text-gray-500">Automated customer follow-up calls</p>
        </div>
        <Card>
          <CardContent className="py-12 text-center">
            <div className="flex flex-col items-center gap-3">
              <div className="p-3 bg-gray-100 rounded-full">
                <Lock className="h-8 w-8 text-gray-400" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900">
                Upgrade to access Voice Agent
              </h3>
              <p className="text-gray-500 max-w-md">
                The AI Voice Agent feature is available on Business and Enterprise plans.
                Upgrade your subscription to enable automated customer follow-up calls.
              </p>
              <Button asChild className="mt-2">
                <a href="/showroom/billing">View Plans</a>
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Voice Agent</h1>
        <p className="text-gray-500">
          Configure automated follow-up calls for new project submissions
        </p>
      </div>

      <Tabs defaultValue="general" className="w-full">
        <TabsList className="grid w-full grid-cols-4">
          <TabsTrigger value="general" className="gap-2">
            <Settings className="h-4 w-4" />
            General
          </TabsTrigger>
          <TabsTrigger value="prompts" className="gap-2">
            <MessageSquare className="h-4 w-4" />
            Prompts & Templates
          </TabsTrigger>
          <TabsTrigger value="flow" className="gap-2">
            <GitBranch className="h-4 w-4" />
            Post-Call Flow
          </TabsTrigger>
          <TabsTrigger value="activity" className="gap-2" onClick={() => setSelectedProjectId(null)}>
            <Activity className="h-4 w-4" />
            Activity
          </TabsTrigger>
        </TabsList>

        {/* ---- General Settings Tab ---- */}
        <TabsContent value="general">
          <Card>
            <CardHeader>
              <CardTitle>General Settings</CardTitle>
              <CardDescription>
                Configure how and when the voice agent contacts customers after a project
                submission.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              {/* Enable toggle */}
              <div className="flex items-center justify-between">
                <div>
                  <Label className="text-base font-semibold">Enable Voice Agent</Label>
                  <p className="text-sm text-gray-500">
                    When enabled, the voice agent will follow up with customers based on
                    your trigger mode.
                  </p>
                </div>
                <Switch checked={enabled} onCheckedChange={setEnabled} />
              </div>

              <Separator />

              {/* Trigger mode */}
              <div className="space-y-3">
                <Label className="text-base font-semibold">Trigger Mode</Label>
                <div className="flex gap-2">
                  {(
                    [
                      { value: 'immediate', label: 'Immediate', desc: 'Call right after submission' },
                      { value: 'delayed', label: 'Delayed', desc: 'Wait before calling' },
                      { value: 'manual', label: 'Manual', desc: 'Trigger from dashboard' },
                    ] as const
                  ).map((mode) => (
                    <button
                      key={mode.value}
                      onClick={() => setTriggerMode(mode.value)}
                      className={`flex-1 p-3 rounded-lg border-2 text-left transition-colors ${
                        triggerMode === mode.value
                          ? 'border-blue-500 bg-blue-50'
                          : 'border-gray-200 hover:border-gray-300'
                      }`}
                    >
                      <p className="font-medium text-sm">{mode.label}</p>
                      <p className="text-xs text-gray-500">{mode.desc}</p>
                    </button>
                  ))}
                </div>
              </div>

              {/* Delay minutes (only shown when delayed) */}
              {triggerMode === 'delayed' && (
                <div className="space-y-2">
                  <Label>Delay (minutes)</Label>
                  <Input
                    type="number"
                    min={1}
                    max={60}
                    value={delayMinutes}
                    onChange={(e) =>
                      setDelayMinutes(
                        Math.max(1, Math.min(60, parseInt(e.target.value) || 1))
                      )
                    }
                    className="w-32"
                  />
                  <p className="text-xs text-gray-500">
                    Wait this many minutes after project submission before calling (1-60).
                  </p>
                </div>
              )}

              <Separator />

              {/* Distance threshold */}
              <div className="space-y-2">
                <Label className="font-semibold">Distance Threshold (miles)</Label>
                <Input
                  type="number"
                  min={1}
                  value={distanceThreshold}
                  onChange={(e) =>
                    setDistanceThreshold(Math.max(1, parseInt(e.target.value) || 30))
                  }
                  className="w-32"
                />
                <p className="text-xs text-gray-500">
                  Customers within this distance are classified as &quot;near&quot; and
                  receive the near-distance script. Others get the far-distance script.
                </p>
              </div>

              <Separator />

              {/* Scheduling link */}
              <div className="space-y-2">
                <Label className="font-semibold">Scheduling Link</Label>
                <Input
                  type="url"
                  value={schedulingLink}
                  onChange={(e) => setSchedulingLink(e.target.value)}
                  placeholder="https://calendly.com/your-showroom"
                />
                <p className="text-xs text-gray-500">
                  URL sent to customers for booking appointments. Available as{' '}
                  <code className="bg-gray-100 px-1 rounded text-xs">
                    {'{{scheduling_link}}'}
                  </code>{' '}
                  in templates.
                </p>
              </div>

              <Separator />

              {/* AI Agent Configuration */}
              <div className="space-y-4">
                <div>
                  <Label className="font-semibold text-base">AI Agent Configuration</Label>
                  <p className="text-xs text-gray-500 mt-1">
                    Customize your AI agent&apos;s voice, model, and personality. Leave blank to use platform defaults.
                    Browse available voices at{' '}
                    <a href="https://docs.vapi.ai/quickstart/phone/outbound#voice-configuration" target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">
                      Vapi Voice Library
                    </a>
                  </p>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="space-y-1.5">
                    <Label>Agent Name</Label>
                    <Input
                      value={agentName}
                      onChange={(e) => setAgentName(e.target.value)}
                      placeholder="scheduling assistant"
                    />
                    <p className="text-xs text-gray-400">Name the AI uses to introduce itself</p>
                  </div>

                  <div className="space-y-1.5">
                    <Label>First Message</Label>
                    <Input
                      value={agentFirstMessage}
                      onChange={(e) => setAgentFirstMessage(e.target.value)}
                      placeholder="Hi, this is the scheduling assistant. How are you today?"
                    />
                    <p className="text-xs text-gray-400">What the AI says when the call connects</p>
                  </div>

                  <div className="space-y-1.5">
                    <Label>LLM Provider</Label>
                    <select
                      value={llmProvider}
                      onChange={(e) => setLlmProvider(e.target.value)}
                      className="w-full border rounded-md px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                      <option value="">Platform Default</option>
                      <option value="openai">OpenAI</option>
                      <option value="anthropic">Anthropic</option>
                      <option value="groq">Groq</option>
                      <option value="together-ai">Together AI</option>
                    </select>
                  </div>

                  <div className="space-y-1.5">
                    <Label>LLM Model</Label>
                    <Input
                      value={llmModel}
                      onChange={(e) => setLlmModel(e.target.value)}
                      placeholder="gpt-4o"
                    />
                    <p className="text-xs text-gray-400">e.g., gpt-4o, gpt-4o-mini, claude-3-5-sonnet</p>
                  </div>

                  <div className="space-y-1.5">
                    <Label>Voice Provider</Label>
                    <select
                      value={voiceProvider}
                      onChange={(e) => setVoiceProvider(e.target.value)}
                      className="w-full border rounded-md px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                      <option value="">Platform Default</option>
                      <option value="11labs">ElevenLabs</option>
                      <option value="openai">OpenAI</option>
                      <option value="deepgram">Deepgram</option>
                      <option value="playht">PlayHT</option>
                      <option value="lmnt">LMNT</option>
                    </select>
                  </div>

                  <div className="space-y-1.5">
                    <Label>Voice ID</Label>
                    <Input
                      value={voiceId}
                      onChange={(e) => setVoiceId(e.target.value)}
                      placeholder="21m00Tcm4TlvDq8ikWAM"
                    />
                    <p className="text-xs text-gray-400">
                      Voice ID from your provider.{' '}
                      <a href="https://docs.vapi.ai/quickstart/phone/outbound#voice-configuration" target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">
                        Browse voices →
                      </a>
                    </p>
                  </div>
                </div>
              </div>

              <Separator />

              {/* Save button */}
              <div className="flex justify-end">
                <Button
                  onClick={saveGeneral}
                  disabled={generalSaving}
                  className="gap-2 min-w-[140px]"
                >
                  {generalSaving ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Saving...
                    </>
                  ) : (
                    <>
                      <Save className="h-4 w-4" />
                      Save Settings
                    </>
                  )}
                </Button>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* ---- Prompts & Templates Tab ---- */}
        <TabsContent value="prompts">
          <Card>
            <CardHeader>
              <CardTitle>Prompts & Templates</CardTitle>
              <CardDescription>
                Customize the SMS message and AI call script for each distance and
                customer type combination. Leave blank to use the platform defaults.
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

              {/* Sub-tabs for distance/type combos */}
              <div className="flex gap-2 flex-wrap">
                {PROMPT_SUBTABS.map((tab) => (
                  <button
                    key={tab.key}
                    onClick={() => setActivePromptTab(tab.key)}
                    className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                      activePromptTab === tab.key
                        ? 'bg-blue-100 text-blue-700'
                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                    }`}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>

              {/* SMS template */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label className="font-semibold">SMS Template</Label>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => resetPrompt(activePromptTab, 'sms')}
                    className="gap-1 text-xs text-gray-500"
                  >
                    <RotateCcw className="h-3 w-3" />
                    Reset to Default
                  </Button>
                </div>
                <Textarea
                  value={smsTemplates[activePromptTab]}
                  onChange={(e) =>
                    setSmsTemplates((prev) => ({
                      ...prev,
                      [activePromptTab]: e.target.value,
                    }))
                  }
                  placeholder={
                    masterSmsDefault || 'Using platform default SMS template...'
                  }
                  className="min-h-[120px] font-mono text-sm"
                />
                {!smsTemplates[activePromptTab] && (
                  <p className="text-xs text-gray-400">
                    No custom template set. The platform default will be used.
                  </p>
                )}
              </div>

              <Separator />

              {/* System prompt */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label className="font-semibold">System Prompt (Call Script)</Label>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => resetPrompt(activePromptTab, 'prompt')}
                    className="gap-1 text-xs text-gray-500"
                  >
                    <RotateCcw className="h-3 w-3" />
                    Reset to Default
                  </Button>
                </div>
                <Textarea
                  value={systemPrompts[activePromptTab]}
                  onChange={(e) =>
                    setSystemPrompts((prev) => ({
                      ...prev,
                      [activePromptTab]: e.target.value,
                    }))
                  }
                  placeholder={
                    masterPromptDefault || 'Using platform default system prompt...'
                  }
                  className="min-h-[250px] font-mono text-sm"
                />
                {!systemPrompts[activePromptTab] && (
                  <p className="text-xs text-gray-400">
                    No custom prompt set. The platform default will be used.
                  </p>
                )}
              </div>

              <Separator />

              {/* Save button */}
              <div className="flex justify-end">
                <Button
                  onClick={savePrompts}
                  disabled={promptsSaving}
                  className="gap-2 min-w-[140px]"
                >
                  {promptsSaving ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Saving...
                    </>
                  ) : (
                    <>
                      <Save className="h-4 w-4" />
                      Save Prompts
                    </>
                  )}
                </Button>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* ---- Post-Call Flow Tab ---- */}
        <TabsContent value="flow">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle>Post-Call Flow</CardTitle>
                  <CardDescription>
                    Design the automated follow-up sequence after the initial call. Drag
                    and drop nodes to build your flow.
                  </CardDescription>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPostCallFlow(DEFAULT_POST_CALL_FLOW)}
                  className="gap-2"
                >
                  <RotateCcw className="h-4 w-4" />
                  Reset to Default Flow
                </Button>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <FlowBuilderWrapper
                flow={postCallFlow}
                onChange={setPostCallFlow}
              />

              <Separator />

              <div className="flex justify-end">
                <Button
                  onClick={saveFlow}
                  disabled={flowSaving}
                  className="gap-2 min-w-[140px]"
                >
                  {flowSaving ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Saving...
                    </>
                  ) : (
                    <>
                      <Save className="h-4 w-4" />
                      Save Flow
                    </>
                  )}
                </Button>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* ---- Activity Tab ---- */}
        <TabsContent value="activity">
          <Card>
            <CardHeader>
              <CardTitle>
                {selectedProjectId ? (
                  <div className="flex items-center gap-3">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setSelectedProjectId(null)}
                      className="gap-1 -ml-2"
                    >
                      <ArrowLeft className="h-4 w-4" />
                      Back to Activity
                    </Button>
                    <span>Flow Debugger</span>
                  </div>
                ) : (
                  'Voice Agent Activity'
                )}
              </CardTitle>
              {!selectedProjectId && (
                <CardDescription>
                  View all voice agent call activity across your projects. Click a row to
                  inspect the flow.
                </CardDescription>
              )}
            </CardHeader>
            <CardContent>
              {selectedProjectId ? (
                FlowDebuggerComponent ? (
                  <div className="h-[600px]">
                    <FlowDebuggerComponent
                      projectId={selectedProjectId}
                      showroomId={showroomId!}
                    />
                  </div>
                ) : (
                  <div className="h-[400px] border-2 border-dashed border-gray-200 rounded-lg flex items-center justify-center">
                    <div className="text-center text-gray-400">
                      <GitBranch className="h-8 w-8 mx-auto mb-2" />
                      <p className="text-sm font-medium">Flow Debugger</p>
                      <p className="text-xs">Loading flow debugger...</p>
                    </div>
                  </div>
                )
              ) : showroomId ? (
                <VoiceAgentActivityList
                  showroomId={showroomId}
                  onSelectProject={setSelectedProjectId}
                />
              ) : null}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}

/**
 * Lazy wrapper for FlowBuilder to avoid SSR issues with ReactFlow.
 * Falls back to a placeholder if FlowBuilder is not yet available.
 */
function FlowBuilderWrapper({
  flow,
  onChange,
}: {
  flow: PostCallFlow
  onChange: (flow: PostCallFlow) => void
}) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [FlowBuilderComponent, setFlowBuilderComponent] = useState<React.ComponentType<any> | null>(null)

  useEffect(() => {
    import('@/components/voice-agent/FlowBuilder')
      .then((mod) => {
        setFlowBuilderComponent(() => mod.FlowBuilder)
      })
      .catch(() => {
        // FlowBuilder not available yet (Wave 1 may not be merged)
        console.warn('FlowBuilder component not available')
      })
  }, [])

  if (!FlowBuilderComponent) {
    return (
      <div className="h-[500px] border-2 border-dashed border-gray-200 rounded-lg flex items-center justify-center">
        <div className="text-center text-gray-400">
          <GitBranch className="h-8 w-8 mx-auto mb-2" />
          <p className="text-sm font-medium">Flow Builder</p>
          <p className="text-xs">Loading visual flow editor...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="h-[500px]">
      <FlowBuilderComponent
        flow={flow as { nodes: unknown[]; edges: unknown[] }}
        onChange={onChange as (f: { nodes: unknown[]; edges: unknown[] }) => void}
      />
    </div>
  )
}
