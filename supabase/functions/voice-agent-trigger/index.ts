// Voice Agent Trigger — Main orchestrator Edge Function
// Handles auto-trigger from submit-project AND manual trigger from dashboard.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import type { VoiceAgentTriggerPayload, VoiceAgentShowroomSettings } from '../_shared/voice-agent/types.ts'
import { sendSms } from '../_shared/voice-agent/twilio.ts'
import { initiateVapiCall } from '../_shared/voice-agent/vapi.ts'
import { calculateDistance, determineZone } from '../_shared/voice-agent/distance.ts'
import { interpolate, buildTemplateVariables } from '../_shared/voice-agent/template.ts'
import { SEND_LINK_TOOL_DEFINITION, DEFAULT_SMS_TEMPLATE, DEFAULT_SYSTEM_PROMPT } from '../_shared/voice-agent/constants.ts'

serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    let payload: VoiceAgentTriggerPayload = await req.json()
    console.log('[VOICE_TRIGGER] Received payload', {
      project_id: payload.project_id,
      showroom_id: payload.showroom_id,
      triggered_by: payload.triggered_by,
    })

    // 1. Validate minimal fields
    if (!payload.project_id || !payload.showroom_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: project_id, showroom_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1b. For manual triggers (or any call without full customer data), auto-fetch from DB
    if (!payload.customer?.phone_normalized) {
      console.log('[VOICE_TRIGGER] No customer data in payload, fetching from database...')

      const { data: project, error: projErr } = await supabaseAdmin
        .from('projects')
        .select('*, customers(*)')
        .eq('id', payload.project_id)
        .single()

      if (projErr || !project) {
        return new Response(
          JSON.stringify({ error: 'Project not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const customer = project.customers || {}
      const customerPhone = customer.phone_normalized || customer.phone || project.customer_phone
      if (!customerPhone) {
        return new Response(
          JSON.stringify({ error: 'No customer phone number available for this project' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const { data: showroom } = await supabaseAdmin
        .from('showrooms')
        .select('name, phone, email, address_line1, city, state, postal_code, showroom_code')
        .eq('id', payload.showroom_id)
        .single()

      payload = {
        project_id: payload.project_id,
        showroom_id: payload.showroom_id,
        triggered_by: payload.triggered_by || 'manual',
        customer: {
          id: customer.id || '',
          first_name: customer.first_name || project.customer_first_name || '',
          last_name: customer.last_name || project.customer_last_name || '',
          phone_normalized: customerPhone,
          email: customer.email || project.customer_email || null,
          customer_type: customer.customer_type || 'homeowner',
          address_line1: customer.address_line1 || null,
          city: customer.city || null,
          state: customer.state || null,
          zip_code: customer.zip_code || null,
        },
        end_client: {
          first_name: null,
          last_name: null,
          phone: null,
          email: null,
          address: null,
        },
        project: {
          name: project.project_name || '',
          reference_number: project.reference_number || '',
          notes: project.project_notes || null,
          status: project.status || 'submitted',
          submitted_at: project.submitted_at || project.created_at || new Date().toISOString(),
        },
        showroom: {
          name: showroom?.name || '',
          phone: showroom?.phone || null,
          email: showroom?.email || null,
          address_line1: showroom?.address_line1 || null,
          city: showroom?.city || null,
          state: showroom?.state || null,
          postal_code: showroom?.postal_code || null,
          showroom_code: showroom?.showroom_code || '',
        },
      }
      console.log('[VOICE_TRIGGER] Built payload from database for', customerPhone)
    }

    // 2. Check global enable
    const { data: vaGlobal } = await supabaseAdmin
      .from('platform_settings')
      .select('value')
      .eq('key', 'voice_agent_globally_enabled')
      .single()

    if (vaGlobal?.value !== 'true') {
      console.log('[VOICE_TRIGGER] Voice agent globally disabled')
      return new Response(
        JSON.stringify({ success: false, message: 'Voice agent is globally disabled' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. Get showroom settings
    const { data: settings, error: settingsError } = await supabaseAdmin
      .from('voice_agent_showroom_settings')
      .select('*')
      .eq('showroom_id', payload.showroom_id)
      .single()

    if (settingsError || !settings) {
      console.log('[VOICE_TRIGGER] No voice agent settings for showroom', payload.showroom_id)
      return new Response(
        JSON.stringify({ success: false, message: 'Voice agent not configured for this showroom' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const vaSettings = settings as VoiceAgentShowroomSettings

    if (!vaSettings.enabled) {
      console.log('[VOICE_TRIGGER] Voice agent disabled for showroom', payload.showroom_id)
      return new Response(
        JSON.stringify({ success: false, message: 'Voice agent disabled for this showroom' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. If trigger_mode is manual AND triggered_by is system (auto-trigger), skip
    if (vaSettings.trigger_mode === 'manual' && payload.triggered_by === 'system') {
      console.log('[VOICE_TRIGGER] Showroom is in manual mode, skipping auto-trigger')
      return new Response(
        JSON.stringify({ success: false, message: 'Showroom is set to manual trigger mode' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. Prevent duplicate active flows (unless from flow-processor retries)
    if (!payload.triggered_by.startsWith('flow-processor')) {
      const { data: existingLogs } = await supabaseAdmin
        .from('voice_agent_logs')
        .select('id')
        .eq('project_id', payload.project_id)
        .not('flow_status', 'in', '("completed","stopped")')

      if (existingLogs && existingLogs.length > 0) {
        console.log('[VOICE_TRIGGER] Active flow already exists for project', payload.project_id)
        return new Response(
          JSON.stringify({ success: false, message: 'Active voice agent flow already exists for this project' }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // 6. Calculate distance
    const customerAddressParts = [
      payload.customer.address_line1,
      payload.customer.city,
      payload.customer.state,
      payload.customer.zip_code,
    ].filter(Boolean)
    const customerAddress = customerAddressParts.join(', ')

    const showroomAddressParts = [
      payload.showroom.address_line1,
      payload.showroom.city,
      payload.showroom.state,
      payload.showroom.postal_code,
    ].filter(Boolean)
    const showroomAddress = showroomAddressParts.join(', ')

    let distanceMiles: number | null = null
    let distanceKm: number | null = null
    let driveTimeMinutes: number | null = null
    let zone: 'near' | 'far' = 'near' // Default to near if no distance data

    const distanceResult = await calculateDistance({
      customerAddress,
      showroomAddress,
    })

    if (distanceResult) {
      distanceMiles = distanceResult.distanceMiles
      distanceKm = distanceResult.distanceKm
      driveTimeMinutes = distanceResult.driveTimeMinutes
      zone = determineZone(distanceMiles, vaSettings.distance_threshold_miles)
    }

    console.log('[VOICE_TRIGGER] Distance result', { distanceMiles, zone })

    // 7. Determine customer type
    const customerType = payload.customer.customer_type || 'homeowner'

    // 8. Select SMS template: showroom override -> platform default
    const smsTemplateKey = `${zone}_${customerType}_sms_template` as keyof VoiceAgentShowroomSettings
    let smsTemplate = vaSettings[smsTemplateKey] as string | null

    if (!smsTemplate) {
      const { data: defaultTemplate } = await supabaseAdmin
        .from('platform_settings')
        .select('value')
        .eq('key', 'va_default_sms_template')
        .single()

      smsTemplate = defaultTemplate?.value || DEFAULT_SMS_TEMPLATE
    }

    // 9. Select system prompt: showroom override -> platform default
    const promptKey = `${zone}_${customerType}_system_prompt` as keyof VoiceAgentShowroomSettings
    let systemPrompt = vaSettings[promptKey] as string | null

    if (!systemPrompt) {
      const { data: defaultPrompt } = await supabaseAdmin
        .from('platform_settings')
        .select('value')
        .eq('key', 'va_default_system_prompt')
        .single()

      systemPrompt = defaultPrompt?.value || DEFAULT_SYSTEM_PROMPT
    }

    // 10. Build template variables
    const distanceData = distanceResult
      ? { distanceMiles: distanceMiles!, distanceKm: distanceKm!, driveTimeMinutes: driveTimeMinutes!, zone }
      : null
    const templateVars = buildTemplateVariables(payload, distanceData)

    // Add scheduling_link to template vars
    if (vaSettings.scheduling_link) {
      templateVars.scheduling_link = vaSettings.scheduling_link
    }

    // 11. Interpolate SMS template
    const smsBody = interpolate(smsTemplate, templateVars)

    // 12. Calculate attempt number
    const { count: existingAttempts } = await supabaseAdmin
      .from('voice_agent_logs')
      .select('id', { count: 'exact', head: true })
      .eq('project_id', payload.project_id)

    const attemptNumber = (existingAttempts || 0) + 1

    // 13. Create voice_agent_logs row
    const { data: logRow, error: logError } = await supabaseAdmin
      .from('voice_agent_logs')
      .insert({
        showroom_id: payload.showroom_id,
        project_id: payload.project_id,
        customer_id: payload.customer.id,
        customer_phone: payload.customer.phone_normalized,
        sms_status: 'pending',
        call_status: 'pending',
        distance_miles: distanceMiles,
        drive_time_minutes: driveTimeMinutes,
        distance_zone: zone,
        customer_type_used: customerType,
        attempt_number: attemptNumber,
        flow_status: 'active',
        trigger_mode: vaSettings.trigger_mode,
        triggered_by: payload.triggered_by,
      })
      .select('id')
      .single()

    if (logError || !logRow) {
      console.error('[VOICE_TRIGGER] Failed to create log row:', logError)
      return new Response(
        JSON.stringify({ error: 'Failed to create voice agent log' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const logId = logRow.id
    console.log('[VOICE_TRIGGER] Created log row', logId)

    // 14. Send SMS
    const smsResult = await sendSms({
      to: payload.customer.phone_normalized,
      body: smsBody,
    })

    if (smsResult.success) {
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({
          sms_status: 'sent',
          sms_sid: smsResult.sid || null,
          sms_sent_at: new Date().toISOString(),
        })
        .eq('id', logId)
    } else {
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({
          sms_status: 'failed',
          sms_error: smsResult.error || 'Unknown SMS error',
        })
        .eq('id', logId)
      console.error('[VOICE_TRIGGER] SMS failed, continuing with call:', smsResult.error)
    }

    // 15. Interpolate system prompt
    const interpolatedPrompt = interpolate(systemPrompt, templateVars)

    // 16. Build Vapi tools array
    const vapiTools: unknown[] = []
    if (vaSettings.scheduling_link) {
      const sendLinkTool = JSON.parse(JSON.stringify(SEND_LINK_TOOL_DEFINITION))
      const supabaseUrl = Deno.env.get('SUPABASE_URL')
      sendLinkTool.server.url = `${supabaseUrl}/functions/v1/voice-agent-send-link`
      vapiTools.push(sendLinkTool)
    }

    // 17. Calculate scheduledAt for delayed triggers
    let scheduledAt: string | undefined
    if (vaSettings.trigger_mode === 'delayed' && vaSettings.delay_minutes > 0) {
      const scheduled = new Date()
      scheduled.setMinutes(scheduled.getMinutes() + vaSettings.delay_minutes)
      scheduledAt = scheduled.toISOString()
    }

    // 18. Initiate Vapi call
    const callResult = await initiateVapiCall({
      customerPhone: payload.customer.phone_normalized,
      systemPrompt: interpolatedPrompt,
      tools: vapiTools,
      scheduledAt,
    })

    if (callResult.success) {
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({
          call_status: scheduledAt ? 'scheduled' : 'initiated',
          vapi_call_id: callResult.callId || null,
          call_scheduled_at: scheduledAt || null,
        })
        .eq('id', logId)
    } else {
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({
          call_status: 'failed',
          call_error: callResult.error || 'Unknown call error',
          flow_status: 'stopped',
        })
        .eq('id', logId)
      console.error('[VOICE_TRIGGER] Call initiation failed:', callResult.error)
    }

    console.log('[VOICE_TRIGGER] Trigger complete', { logId, sms: smsResult.success, call: callResult.success })

    return new Response(
      JSON.stringify({ success: true, logId }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[VOICE_TRIGGER] Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
