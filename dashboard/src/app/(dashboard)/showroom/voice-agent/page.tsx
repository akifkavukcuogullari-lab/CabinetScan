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
    // 10 outcome nodes — one per possible call result, laid out vertically on the left
    { id: 'no_answer', type: 'outcome', data: { outcome: 'no_answer', label: 'No Answer' }, position: { x: 0, y: 0 } },
    { id: 'line_busy', type: 'outcome', data: { outcome: 'line_busy', label: 'Line Busy' }, position: { x: 0, y: 150 } },
    { id: 'voicemail', type: 'outcome', data: { outcome: 'voicemail', label: 'Voicemail' }, position: { x: 0, y: 300 } },
    { id: 'ghosted', type: 'outcome', data: { outcome: 'ghosted', label: 'Ghosted' }, position: { x: 0, y: 450 } },
    { id: 'interested', type: 'outcome', data: { outcome: 'interested', label: 'Interested' }, position: { x: 0, y: 600 } },
    { id: 'not_interested', type: 'outcome', data: { outcome: 'not_interested', label: 'Not Interested' }, position: { x: 0, y: 750 } },
    { id: 'link_sent', type: 'outcome', data: { outcome: 'link_sent', label: 'Link Sent' }, position: { x: 0, y: 900 } },
    { id: 'callback_requested', type: 'outcome', data: { outcome: 'callback_requested', label: 'Callback Requested' }, position: { x: 0, y: 1050 } },
    { id: 'hung_up_early', type: 'outcome', data: { outcome: 'hung_up_early', label: 'Hung Up Early' }, position: { x: 0, y: 1200 } },
    { id: 'technical_error', type: 'outcome', data: { outcome: 'technical_error', label: 'Technical Error' }, position: { x: 0, y: 1350 } },

    // No Answer flow
    { id: 'na_wait', type: 'wait', data: { mode: 'next_business_day', hours: 24 }, position: { x: 300, y: 0 } },
    { id: 'na_retry', type: 'retryCall', data: { maxAttempts: 3 }, position: { x: 550, y: 0 } },
    { id: 'na_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we tried reaching you about your project at {{showroom_name}}. Call us at {{showroom_phone}} or book a visit: {{scheduling_link}}' }, position: { x: 800, y: 50 } },
    { id: 'na_stop', type: 'stop', data: {}, position: { x: 1050, y: 50 } },

    // Line Busy flow
    { id: 'lb_wait', type: 'wait', data: { hours: 1 }, position: { x: 300, y: 150 } },
    { id: 'lb_retry', type: 'retryCall', data: { maxAttempts: 3 }, position: { x: 550, y: 150 } },
    { id: 'lb_stop', type: 'stop', data: {}, position: { x: 800, y: 150 } },

    // Voicemail flow
    { id: 'vm_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we left you a voicemail about your project at {{showroom_name}}. Book your showroom visit here: {{scheduling_link}}' }, position: { x: 300, y: 300 } },
    { id: 'vm_stop', type: 'stop', data: {}, position: { x: 600, y: 300 } },

    // Ghosted flow
    { id: 'gh_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, sorry we missed you! When you are ready to discuss your project at {{showroom_name}}, book a visit: {{scheduling_link}}' }, position: { x: 300, y: 450 } },
    { id: 'gh_stop', type: 'stop', data: {}, position: { x: 600, y: 450 } },

    // Interested flow
    { id: 'int_sms', type: 'sms', data: { template: "Here's your link to schedule a visit: {{scheduling_link}}" }, position: { x: 300, y: 600 } },
    { id: 'int_stop', type: 'stop', data: {}, position: { x: 600, y: 600 } },

    // Not interested → stop
    { id: 'ni_stop', type: 'stop', data: {}, position: { x: 300, y: 750 } },

    // Link sent → stop
    { id: 'ls_stop', type: 'stop', data: {}, position: { x: 300, y: 900 } },

    // Callback requested flow
    { id: 'cb_wait', type: 'wait', data: { hours: 4 }, position: { x: 300, y: 1050 } },
    { id: 'cb_retry', type: 'retryCall', data: { maxAttempts: 2 }, position: { x: 550, y: 1050 } },
    { id: 'cb_stop', type: 'stop', data: {}, position: { x: 800, y: 1050 } },

    // Hung up early flow
    { id: 'hu_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, this is {{showroom_name}}. We just tried calling about your project. Book a visit at your convenience: {{scheduling_link}}' }, position: { x: 300, y: 1200 } },
    { id: 'hu_stop', type: 'stop', data: {}, position: { x: 600, y: 1200 } },

    // Technical error flow
    { id: 'te_retry', type: 'retryCall', data: { maxAttempts: 1 }, position: { x: 300, y: 1350 } },
    { id: 'te_stop', type: 'stop', data: {}, position: { x: 550, y: 1350 } },
  ],
  edges: [
    { source: 'no_answer', target: 'na_wait' },
    { source: 'na_wait', target: 'na_retry' },
    { source: 'na_retry', target: 'na_sms', sourceHandle: 'max_reached' },
    { source: 'na_sms', target: 'na_stop' },
    { source: 'line_busy', target: 'lb_wait' },
    { source: 'lb_wait', target: 'lb_retry' },
    { source: 'lb_retry', target: 'lb_stop', sourceHandle: 'max_reached' },
    { source: 'voicemail', target: 'vm_sms' },
    { source: 'vm_sms', target: 'vm_stop' },
    { source: 'ghosted', target: 'gh_sms' },
    { source: 'gh_sms', target: 'gh_stop' },
    { source: 'interested', target: 'int_sms' },
    { source: 'int_sms', target: 'int_stop' },
    { source: 'not_interested', target: 'ni_stop' },
    { source: 'link_sent', target: 'ls_stop' },
    { source: 'callback_requested', target: 'cb_wait' },
    { source: 'cb_wait', target: 'cb_retry' },
    { source: 'cb_retry', target: 'cb_stop', sourceHandle: 'max_reached' },
    { source: 'hung_up_early', target: 'hu_sms' },
    { source: 'hu_sms', target: 'hu_stop' },
    { source: 'technical_error', target: 'te_retry' },
    { source: 'te_retry', target: 'te_stop', sourceHandle: 'max_reached' },
  ],
}

// Default system prompts for kitchen cabinet showrooms
const DEFAULT_SYSTEM_PROMPTS: Record<string, string> = {
  near_homeowner: `You are a warm, professional scheduling assistant calling on behalf of {{showroom_name}}, a kitchen cabinet showroom. You are calling {{customer_full_name}}, a homeowner who recently submitted a kitchen project and lives approximately {{distance_miles}} miles away (about {{drive_time}} drive).

Your goal is to schedule an in-person showroom visit. Follow these guidelines:

1. INTRODUCTION: "Hi {{customer_name}}, this is the team at {{showroom_name}} calling! We received your kitchen project submission and we'd love to help bring your vision to life."

2. REFERENCE THEIR PROJECT: Mention you saw their kitchen project and are excited to help them explore cabinet options in person.

3. PROXIMITY ADVANTAGE: Since they are nearby, emphasize convenience. "You're just a short drive away — we'd love to have you visit our showroom to see the cabinets and finishes in person."

4. SCHEDULING: Offer flexible scheduling. "Would any day this week or next work for you? We're open Monday through Saturday." If they are interested, use the send_scheduling_link tool to text them a booking link.

5. KEEP IT SHORT: Stay under 2 minutes. Be conversational, not scripted.

6. NEVER discuss pricing, quotes, or specific costs. Say "Our design team can walk you through all the options and pricing when you visit."

7. If they are not interested, thank them politely and end the call gracefully.`,

  near_contractor: `You are a warm, professional scheduling assistant calling on behalf of {{showroom_name}}, a kitchen cabinet showroom. You are calling {{customer_full_name}}, a contractor who recently submitted a kitchen project and is located approximately {{distance_miles}} miles away (about {{drive_time}} drive).

Your goal is to schedule a showroom visit or project consultation. Follow these guidelines:

1. INTRODUCTION: "Hi {{customer_name}}, this is the team at {{showroom_name}}! We received the project submission you sent over and wanted to connect with you."

2. PROFESSIONAL TONE: Speak contractor-to-contractor. They are busy — be efficient and respect their time.

3. VALUE PROPOSITION: "We work with a lot of contractors in the area and can offer trade pricing, quick turnaround, and dedicated project support for your client's kitchen."

4. PROXIMITY: "Since you're nearby, it'd be easy to swing by our showroom to review samples and discuss the project details."

5. SCHEDULING: "Do you have 20-30 minutes this week to stop by, or would you prefer we set up a quick call with our design team?" If interested, use the send_scheduling_link tool to send a booking link.

6. KEEP IT SHORT: Under 2 minutes. Be direct and professional.

7. NEVER discuss specific pricing on the call. Direct pricing discussions to an in-person or follow-up meeting.

8. If they are not interested, thank them and end the call professionally.`,

  far_homeowner: `You are a warm, professional scheduling assistant calling on behalf of {{showroom_name}}, a kitchen cabinet showroom. You are calling {{customer_full_name}}, a homeowner who recently submitted a kitchen project and lives approximately {{distance_miles}} miles away (about {{drive_time}} drive).

Your goal is to schedule either a virtual consultation or an in-person showroom visit. Follow these guidelines:

1. INTRODUCTION: "Hi {{customer_name}}, this is the team at {{showroom_name}} calling! We received your kitchen project submission and we're excited to help."

2. ACKNOWLEDGE DISTANCE: "I see you're about {{distance_miles}} miles from our showroom. We have a couple of great options to make this easy for you."

3. OFFER OPTIONS:
   - "We can set up a virtual design consultation where our team walks you through cabinet styles, finishes, and options over video call."
   - "Or if you're planning to be in the area, we'd love to have you visit the showroom in person."

4. SCHEDULING: "Which would work better for you?" If interested, use the send_scheduling_link tool to text them a booking link.

5. KEEP IT SHORT: Under 2 minutes. Be warm and accommodating.

6. NEVER discuss pricing or quotes on the call.

7. If they are not interested, thank them politely and end the call gracefully.`,

  far_contractor: `You are a warm, professional scheduling assistant calling on behalf of {{showroom_name}}, a kitchen cabinet showroom. You are calling {{customer_full_name}}, a contractor who recently submitted a kitchen project and is located approximately {{distance_miles}} miles away (about {{drive_time}} drive).

Your goal is to schedule a virtual consultation or phone meeting to discuss the project. Follow these guidelines:

1. INTRODUCTION: "Hi {{customer_name}}, this is the team at {{showroom_name}}! We received the project you submitted and wanted to connect."

2. PROFESSIONAL TONE: Be efficient. Contractors are busy.

3. ACKNOWLEDGE DISTANCE: "I know you're a bit of a drive from our showroom, so let me suggest a couple of ways we can work together."

4. OFFER OPTIONS:
   - "We can do a quick virtual meeting to go over the project specs, cabinet selections, and trade pricing."
   - "We also ship samples and can set up a dedicated project manager for your account."

5. SCHEDULING: "Would a 20-minute call this week work?" If interested, use the send_scheduling_link tool to send a booking link.

6. KEEP IT SHORT: Under 2 minutes. Be direct and solution-oriented.

7. NEVER discuss specific pricing on the call. Say "Our team will put together a detailed trade quote after we review the project together."

8. If they are not interested, thank them and end professionally.`,
}

const TEMPLATE_VARIABLES = [
  { name: '{{agent_name}}', desc: 'Voice agent name (e.g., Sarah)' },
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
  const [creditBalanceCents, setCreditBalanceCents] = useState<number | null>(null)

  // Settings
  const [settings, setSettings] = useState<VoiceAgentShowroomSettings | null>(null)
  const [loading, setLoading] = useState(true)

  // General tab state
  const [enabled, setEnabled] = useState(false)
  const [triggerMode, setTriggerMode] = useState<TriggerMode>('manual')
  const [delayMinutes, setDelayMinutes] = useState(15)
  const [distanceThreshold, setDistanceThreshold] = useState(30)
  const [schedulingLink, setSchedulingLink] = useState('')
  const [agentName, setAgentName] = useState('Layla')
  const [llmProvider, setLlmProvider] = useState('openai')
  const [llmModel, setLlmModel] = useState('gpt-4o-mini')
  const [voiceProvider, setVoiceProvider] = useState('11labs')
  const [voiceId, setVoiceId] = useState('DtsPFCrhbCbbJkwZsb3d')
  const [agentFirstMessage, setAgentFirstMessage] = useState('Hi {{customer_name}}, this is {{agent_name}} from {{showroom_name}}! I\'m calling about the kitchen project you recently submitted. Do you have a quick minute?')
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
    near_homeowner: DEFAULT_SYSTEM_PROMPTS.near_homeowner,
    near_contractor: DEFAULT_SYSTEM_PROMPTS.near_contractor,
    far_homeowner: DEFAULT_SYSTEM_PROMPTS.far_homeowner,
    far_contractor: DEFAULT_SYSTEM_PROMPTS.far_contractor,
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

        // Fetch credit balance
        const { data: balanceData } = await supabase
          .from('showroom_credit_balances')
          .select('balance_cents')
          .eq('showroom_id', showroomUser.showroom_id)
          .single()
        setCreditBalanceCents(balanceData?.balance_cents ?? 0)

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
          setAgentName((s as any).agent_name || 'Layla')
          setLlmProvider((s as any).llm_provider || 'openai')
          setLlmModel((s as any).llm_model || 'gpt-4o-mini')
          setVoiceProvider((s as any).voice_provider || '11labs')
          setVoiceId((s as any).voice_id || 'DtsPFCrhbCbbJkwZsb3d')
          setAgentFirstMessage((s as any).first_message || 'Hi {{customer_name}}, this is {{agent_name}} from {{showroom_name}}! I\'m calling about the kitchen project you recently submitted. Do you have a quick minute?')

          setSmsTemplates({
            near_homeowner: s.near_homeowner_sms_template || '',
            near_contractor: s.near_contractor_sms_template || '',
            far_homeowner: s.far_homeowner_sms_template || '',
            far_contractor: s.far_contractor_sms_template || '',
          })
          setSystemPrompts({
            near_homeowner: s.near_homeowner_system_prompt || DEFAULT_SYSTEM_PROMPTS.near_homeowner,
            near_contractor: s.near_contractor_system_prompt || DEFAULT_SYSTEM_PROMPTS.near_contractor,
            far_homeowner: s.far_homeowner_system_prompt || DEFAULT_SYSTEM_PROMPTS.far_homeowner,
            far_contractor: s.far_contractor_system_prompt || DEFAULT_SYSTEM_PROMPTS.far_contractor,
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
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Voice Agent</h1>
          <p className="text-gray-500">
            Configure automated follow-up calls for new project submissions
          </p>
        </div>
        {creditBalanceCents !== null && (
          <a href="/showroom/billing" className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-gray-50 border hover:bg-gray-100 transition-colors">
            <span className="text-xs text-gray-500">Credits</span>
            <span className={`text-sm font-semibold ${creditBalanceCents <= 0 ? 'text-red-600' : 'text-gray-900'}`}>
              ${(creditBalanceCents / 100).toFixed(2)}
            </span>
          </a>
        )}
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
                <p className="text-xs text-gray-500">When should the voice agent fire?</p>
                <div className="flex gap-2">
                  {(
                    [
                      { value: 'immediate', label: 'Automatic', desc: 'Fires on project submission' },
                      { value: 'manual', label: 'Manual', desc: 'Trigger from dashboard only' },
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

              {/* Call delay — independent of trigger mode */}
              <div className="space-y-2">
                <Label className="text-base font-semibold">Call Delay</Label>
                <p className="text-xs text-gray-500">
                  Delay between sending the SMS and making the call. Set to 0 for no delay.
                </p>
                <div className="flex items-center gap-2">
                  <Input
                    type="number"
                    min={0}
                    max={60}
                    value={delayMinutes}
                    onChange={(e) =>
                      setDelayMinutes(
                        Math.max(0, Math.min(60, parseInt(e.target.value) || 0))
                      )
                    }
                    className="w-24"
                  />
                  <span className="text-sm text-gray-500">minutes</span>
                </div>
                {delayMinutes > 0 && (
                  <p className="text-xs text-blue-600">
                    SMS will be sent immediately, call will be made {delayMinutes} minute{delayMinutes !== 1 ? 's' : ''} later.
                  </p>
                )}
              </div>

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
                    <a href="https://elevenlabs.io/voice-library" target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">
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
                      <a href="https://elevenlabs.io/voice-library" target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">
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
              {/* Variable hints — same format as Prompts & Templates section */}
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
                    <span>Call Details</span>
                  </div>
                ) : (
                  'Voice Agent Activity'
                )}
              </CardTitle>
              {!selectedProjectId && (
                <CardDescription>
                  View all voice agent call activity across your projects. Click a row to
                  see call details.
                </CardDescription>
              )}
            </CardHeader>
            <CardContent>
              {selectedProjectId ? (
                <ProjectCallDetails
                  projectId={selectedProjectId}
                  showroomId={showroomId!}
                  flowDebuggerComponent={FlowDebuggerComponent}
                />
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
 * Inline pipeline showing the end-to-end call flow with status per step.
 * SMS → Call → Outcome — each step colored by success/failure/pending.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CallPipeline({ log }: { log: any }) {
  const [expandedStep, setExpandedStep] = useState<string | null>(null)

  // SMS step
  const smsStatus =
    log.sms_status === 'delivered' || log.sms_status === 'sent' ? 'success' :
    log.sms_status === 'failed' ? 'failed' :
    log.sms_status === 'queued' ? 'waiting' :
    'pending'

  // Call step
  const callStatus =
    log.call_status === 'completed' ? 'success' :
    log.call_status === 'failed' || log.call_error ? 'failed' :
    log.call_status === 'in-progress' || log.call_status === 'scheduled' ? 'waiting' :
    'pending'

  // Outcome step (only if call ended)
  const outcomeStatus =
    log.outcome === 'interested' || log.outcome === 'link_sent' ? 'success' :
    log.outcome === 'not_interested' || log.outcome === 'technical_error' || log.outcome === 'hung_up_early' ? 'failed' :
    log.outcome ? 'success' :
    'pending'

  const steps = [
    {
      key: 'sms',
      label: 'SMS',
      status: smsStatus,
      detail: log.sms_status === 'failed' ? log.sms_error : log.sms_status,
      hasDetails: !!(log.sms_error || log.sms_sid || log.sms_sent_at),
    },
    {
      key: 'call',
      label: 'Call',
      status: callStatus,
      detail: log.call_status === 'scheduled' && log.call_scheduled_at
        ? `Scheduled ${new Date(log.call_scheduled_at).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}`
        : log.call_status === 'completed' && log.call_duration_seconds
          ? `${Math.floor(log.call_duration_seconds / 60)}m ${log.call_duration_seconds % 60}s`
          : log.call_error || log.call_status,
      hasDetails: !!(log.call_error || log.vapi_call_id || log.call_scheduled_at || log.call_duration_seconds),
    },
    {
      key: 'outcome',
      label: 'Outcome',
      status: outcomeStatus,
      detail: log.outcome ? log.outcome.replace(/_/g, ' ') : 'pending',
      hasDetails: !!(log.outcome || log.vapi_ended_reason || log.call_summary),
    },
  ]

  const statusColors: Record<string, { bg: string; border: string; text: string; icon: string; hover: string }> = {
    success: { bg: 'bg-green-50', border: 'border-green-300', text: 'text-green-800', icon: 'text-green-600', hover: 'hover:bg-green-100' },
    failed:  { bg: 'bg-red-50',   border: 'border-red-300',   text: 'text-red-800',   icon: 'text-red-600',   hover: 'hover:bg-red-100'   },
    waiting: { bg: 'bg-yellow-50',border: 'border-yellow-300',text: 'text-yellow-800',icon: 'text-yellow-600',hover: 'hover:bg-yellow-100'},
    pending: { bg: 'bg-gray-50',  border: 'border-gray-200',  text: 'text-gray-400',  icon: 'text-gray-300',  hover: 'hover:bg-gray-100'  },
  }

  const expanded = steps.find((s) => s.key === expandedStep)

  return (
    <div className="space-y-3">
      <div className="flex items-stretch gap-2 overflow-x-auto pb-1">
        {steps.map((step, idx) => {
          const colors = statusColors[step.status]
          const nextStepBlocked = step.status === 'failed' && idx < steps.length - 1
          const isExpanded = expandedStep === step.key
          return (
            <div key={step.label} className="flex items-stretch gap-2">
              <button
                type="button"
                onClick={() => setExpandedStep(isExpanded ? null : step.key)}
                disabled={!step.hasDetails}
                className={`flex-1 min-w-[140px] rounded-lg border-2 ${colors.border} ${colors.bg} ${step.hasDetails ? `cursor-pointer ${colors.hover}` : 'cursor-default'} ${isExpanded ? 'ring-2 ring-blue-400 ring-offset-1' : ''} px-3 py-2 text-left transition-colors`}
              >
                <div className="flex items-center gap-1.5">
                  {step.status === 'success' && <span className={colors.icon}>✓</span>}
                  {step.status === 'failed' && <span className={colors.icon}>✗</span>}
                  {step.status === 'waiting' && <span className={colors.icon}>⏳</span>}
                  {step.status === 'pending' && <span className={colors.icon}>○</span>}
                  <span className={`text-xs font-semibold ${colors.text}`}>{step.label}</span>
                </div>
                <p className={`text-[10px] mt-0.5 truncate ${colors.text} opacity-80`}>{step.detail}</p>
              </button>
              {idx < steps.length - 1 && (
                <div className="flex items-center">
                  <svg className={`h-4 w-4 ${nextStepBlocked ? 'text-red-300' : 'text-gray-300'}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                  </svg>
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Expanded step details */}
      {expanded && (
        <div className="rounded-lg border bg-white p-3 space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500">{expanded.label} Details</h4>
            <button onClick={() => setExpandedStep(null)} className="text-gray-400 hover:text-gray-600">
              <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {expanded.key === 'sms' && (
            <div className="space-y-2 text-xs">
              <div className="flex justify-between">
                <span className="text-gray-500">Status</span>
                <span className="font-medium capitalize">{log.sms_status}</span>
              </div>
              {log.sms_sid && (
                <div className="flex justify-between gap-2">
                  <span className="text-gray-500">Twilio SID</span>
                  <span className="font-mono text-[10px] truncate">{log.sms_sid}</span>
                </div>
              )}
              {log.sms_sent_at && (
                <div className="flex justify-between">
                  <span className="text-gray-500">Sent at</span>
                  <span>{new Date(log.sms_sent_at).toLocaleString()}</span>
                </div>
              )}
              {log.sms_error && (
                <div className="mt-2 rounded border border-red-200 bg-red-50 p-2">
                  <p className="text-[10px] font-semibold text-red-800 uppercase mb-1">Error</p>
                  <p className="text-xs text-red-700">{log.sms_error}</p>
                </div>
              )}
            </div>
          )}

          {expanded.key === 'call' && (
            <div className="space-y-2 text-xs">
              <div className="flex justify-between">
                <span className="text-gray-500">Status</span>
                <span className="font-medium">{log.call_status}</span>
              </div>
              {log.vapi_call_id && (
                <div className="flex justify-between gap-2">
                  <span className="text-gray-500">Vapi Call ID</span>
                  <span className="font-mono text-[10px] truncate">{log.vapi_call_id}</span>
                </div>
              )}
              {log.call_scheduled_at && (
                <div className="flex justify-between">
                  <span className="text-gray-500">Scheduled for</span>
                  <span>{new Date(log.call_scheduled_at).toLocaleString()}</span>
                </div>
              )}
              {log.call_started_at && (
                <div className="flex justify-between">
                  <span className="text-gray-500">Started at</span>
                  <span>{new Date(log.call_started_at).toLocaleString()}</span>
                </div>
              )}
              {log.call_ended_at && (
                <div className="flex justify-between">
                  <span className="text-gray-500">Ended at</span>
                  <span>{new Date(log.call_ended_at).toLocaleString()}</span>
                </div>
              )}
              {log.call_duration_seconds != null && (
                <div className="flex justify-between">
                  <span className="text-gray-500">Duration</span>
                  <span>{Math.floor(log.call_duration_seconds / 60)}m {log.call_duration_seconds % 60}s</span>
                </div>
              )}
              {log.call_error && (
                <div className="mt-2 rounded border border-red-200 bg-red-50 p-2">
                  <p className="text-[10px] font-semibold text-red-800 uppercase mb-1">Error</p>
                  <p className="text-xs text-red-700">{log.call_error}</p>
                </div>
              )}
            </div>
          )}

          {expanded.key === 'outcome' && (
            <div className="space-y-2 text-xs">
              {log.outcome && (
                <div className="flex justify-between">
                  <span className="text-gray-500">Outcome</span>
                  <span className="font-medium capitalize">{(log.outcome as string).replace(/_/g, ' ')}</span>
                </div>
              )}
              {log.vapi_ended_reason && (
                <div className="flex justify-between gap-2">
                  <span className="text-gray-500">Ended reason</span>
                  <span className="font-mono text-[10px]">{log.vapi_ended_reason.replace(/-/g, ' ')}</span>
                </div>
              )}
              {log.call_summary && (
                <div className="mt-2 rounded border bg-gray-50 p-2">
                  <p className="text-[10px] font-semibold text-gray-600 uppercase mb-1">Summary</p>
                  <p className="text-xs text-gray-700">{log.call_summary}</p>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

/**
 * Shows all call attempts for a project with full details per attempt.
 */
function ProjectCallDetails({
  projectId,
  showroomId,
  flowDebuggerComponent: FlowDebuggerComp,
}: {
  projectId: string
  showroomId: string
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  flowDebuggerComponent: React.ComponentType<any> | null
}) {
  const supabase = createClient()
  const [logs, setLogs] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [expandedLog, setExpandedLog] = useState<string | null>(null)
  const [showFlowDebugger, setShowFlowDebugger] = useState(false)
  const [logCosts, setLogCosts] = useState<Record<string, number>>({})

  useEffect(() => {
    async function load() {
      setLoading(true)
      const { data } = await supabase
        .from('voice_agent_logs')
        .select('*, projects(customer_first_name, customer_last_name, reference_number, customer_phone)')
        .eq('project_id', projectId)
        .eq('showroom_id', showroomId)
        .order('attempt_number', { ascending: true })

      const logs = data || []
      setLogs(logs)

      // Fetch costs for all logs
      if (logs.length > 0) {
        const logIds = logs.map((l: any) => l.id)
        const { data: txns } = await supabase
          .from('showroom_credit_transactions')
          .select('reference_id, billed_cost_cents')
          .in('reference_id', logIds)
          .eq('reference_type', 'voice_agent_log')

        if (txns) {
          const costMap: Record<string, number> = {}
          for (const t of txns) costMap[t.reference_id] = t.billed_cost_cents
          setLogCosts(costMap)
        }
      }

      setLoading(false)
    }
    load()
  }, [supabase, projectId, showroomId])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
      </div>
    )
  }

  if (logs.length === 0) {
    return <p className="text-sm text-gray-400 py-8 text-center">No call attempts found.</p>
  }

  const project = logs[0]?.projects
  const OUTCOME_COLORS_MAP: Record<string, string> = {
    no_answer: 'bg-yellow-100 text-yellow-800',
    line_busy: 'bg-yellow-100 text-yellow-800',
    voicemail: 'bg-blue-100 text-blue-800',
    ghosted: 'bg-gray-100 text-gray-800',
    interested: 'bg-green-100 text-green-800',
    not_interested: 'bg-red-100 text-red-800',
    link_sent: 'bg-purple-100 text-purple-800',
    callback_requested: 'bg-indigo-100 text-indigo-800',
    hung_up_early: 'bg-orange-100 text-orange-800',
    technical_error: 'bg-red-100 text-red-800',
  }
  const FLOW_COLORS: Record<string, string> = {
    active: 'bg-blue-100 text-blue-800',
    waiting: 'bg-yellow-100 text-yellow-800',
    completed: 'bg-green-100 text-green-800',
    stopped: 'bg-gray-100 text-gray-800',
  }

  return (
    <div className="space-y-4">
      {/* Customer header */}
      {project && (
        <div className="flex items-center gap-3 pb-3 border-b">
          <div>
            <p className="font-semibold">{project.customer_first_name} {project.customer_last_name}</p>
            <p className="text-sm text-gray-500">
              Ref: <span className="font-mono">{project.reference_number}</span>
              {project.customer_phone && <> &middot; {project.customer_phone}</>}
            </p>
          </div>
          <div className="ml-auto">
            <Badge variant="outline" className="text-xs">{logs.length} attempt{logs.length !== 1 ? 's' : ''}</Badge>
          </div>
        </div>
      )}

      {/* Attempt list */}
      {logs.map((log) => {
        const isExpanded = expandedLog === log.id

        return (
          <div key={log.id} className="border rounded-lg overflow-hidden">
            {/* Attempt header — clickable */}
            <button
              onClick={() => setExpandedLog(isExpanded ? null : log.id)}
              className="w-full flex items-center gap-3 p-3 hover:bg-gray-50 transition-colors text-left"
            >
              <Badge variant="outline" className="font-mono text-xs shrink-0">
                #{log.attempt_number}
              </Badge>

              <div className="flex items-center gap-2 flex-wrap flex-1 min-w-0">
                {log.flow_status && (
                  <Badge className={`text-[10px] ${FLOW_COLORS[log.flow_status] || 'bg-gray-100 text-gray-800'}`}>
                    {log.flow_status}
                  </Badge>
                )}
                {log.outcome && (
                  <Badge className={`text-[10px] ${OUTCOME_COLORS_MAP[log.outcome] || 'bg-gray-100 text-gray-800'}`}>
                    {(log.outcome as string).replace(/_/g, ' ')}
                  </Badge>
                )}
                <Badge variant="outline" className="text-[10px]">
                  Call: {log.call_status}
                </Badge>
                <Badge
                  variant="outline"
                  className={`text-[10px] ${
                    log.sms_status === 'delivered' ? 'border-green-200 text-green-700 bg-green-50' :
                    log.sms_status === 'failed' ? 'border-red-200 text-red-700 bg-red-50' :
                    log.sms_status === 'queued' || log.sms_status === 'sent' ? 'border-yellow-200 text-yellow-700 bg-yellow-50' :
                    ''
                  }`}
                  title={log.sms_error || undefined}
                >
                  SMS: {log.sms_status}{log.sms_error ? ' ⚠' : ''}
                </Badge>
              </div>

              <span className="text-xs text-gray-400 shrink-0">
                {new Date(log.created_at).toLocaleString(undefined, {
                  month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
                })}
              </span>

              <svg className={`h-4 w-4 text-gray-400 shrink-0 transition-transform ${isExpanded ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            {/* Expanded details */}
            {isExpanded && (
              <div className="border-t p-4 space-y-4 bg-gray-50/50">
                {/* Inline call pipeline — end-to-end visualization */}
                <div>
                  <p className="text-xs font-semibold text-gray-500 mb-2 uppercase tracking-wider">Call Pipeline</p>
                  <CallPipeline log={log} />
                </div>

                {/* Context details — only what's NOT in the pipeline */}
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  {log.distance_miles != null && (
                    <div>
                      <p className="text-[10px] text-gray-400 uppercase">Distance</p>
                      <p className="text-sm font-medium">{log.distance_miles.toFixed(1)} mi</p>
                    </div>
                  )}
                  {log.drive_time_minutes != null && (
                    <div>
                      <p className="text-[10px] text-gray-400 uppercase">Drive Time</p>
                      <p className="text-sm font-medium">{log.drive_time_minutes} min</p>
                    </div>
                  )}
                  {log.distance_zone && (
                    <div>
                      <p className="text-[10px] text-gray-400 uppercase">Zone</p>
                      <p className="text-sm font-medium capitalize">{log.distance_zone}</p>
                    </div>
                  )}
                  {log.customer_type_used && (
                    <div>
                      <p className="text-[10px] text-gray-400 uppercase">Customer Type</p>
                      <p className="text-sm font-medium capitalize">{log.customer_type_used}</p>
                    </div>
                  )}
                  {log.trigger_mode && (
                    <div>
                      <p className="text-[10px] text-gray-400 uppercase">Trigger</p>
                      <p className="text-sm font-medium capitalize">{log.trigger_mode} / {log.triggered_by}</p>
                    </div>
                  )}
                  {logCosts[log.id] != null && (
                    <div>
                      <p className="text-[10px] text-gray-400 uppercase">Cost</p>
                      <p className="text-sm font-medium">${(logCosts[log.id] / 100).toFixed(2)}</p>
                    </div>
                  )}
                </div>

                {/* Transcript (only when call has ended) */}
                {log.call_transcript && (
                  <div>
                    <p className="text-xs font-semibold text-gray-500 mb-1">Transcript</p>
                    <pre className="text-xs text-gray-600 bg-white p-3 rounded border whitespace-pre-wrap max-h-64 overflow-y-auto leading-relaxed">
                      {log.call_transcript}
                    </pre>
                  </div>
                )}
              </div>
            )}
          </div>
        )
      })}

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
