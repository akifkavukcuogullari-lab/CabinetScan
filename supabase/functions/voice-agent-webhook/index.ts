// Voice Agent Webhook — Vapi callback handler Edge Function
// Receives call events from Vapi and processes end-of-call outcomes.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import type { PostCallFlow, FlowNode, FlowEdge, SimplifiedOutcome } from '../_shared/voice-agent/types.ts'
import { mapVapiOutcome, DEFAULT_POST_CALL_FLOW } from '../_shared/voice-agent/constants.ts'
import { sendSms } from '../_shared/voice-agent/twilio.ts'
import { interpolate, buildTemplateVariables } from '../_shared/voice-agent/template.ts'

/**
 * Find the next node in a flow given a source node ID and optional sourceHandle.
 */
function findNextNode(
  flow: PostCallFlow,
  sourceId: string,
  sourceHandle?: string
): FlowNode | null {
  const edge = flow.edges.find(
    (e) =>
      e.source === sourceId &&
      (sourceHandle ? e.sourceHandle === sourceHandle : !e.sourceHandle)
  )
  if (!edge) return null
  return flow.nodes.find((n) => n.id === edge.target) || null
}

/**
 * Rebuild trigger payload from database records for template interpolation.
 */
async function rebuildPayloadFromLog(logId: string) {
  const { data: log } = await supabaseAdmin
    .from('voice_agent_logs')
    .select('*')
    .eq('id', logId)
    .single()

  if (!log) return null

  // Fetch project
  const { data: project } = await supabaseAdmin
    .from('projects')
    .select('id, project_name, reference_number, project_notes, status, submitted_at')
    .eq('id', log.project_id)
    .single()

  // Fetch customer
  const { data: customer } = await supabaseAdmin
    .from('customers')
    .select('id, first_name, last_name, phone_normalized, email, customer_type, address_line1, city, state, zip_code')
    .eq('id', log.customer_id)
    .single()

  // Fetch showroom
  const { data: showroom } = await supabaseAdmin
    .from('showrooms')
    .select('id, name, phone, email, address_line1, city, state, postal_code, showroom_code')
    .eq('id', log.showroom_id)
    .single()

  if (!project || !customer || !showroom) return null

  return {
    project_id: project.id,
    showroom_id: showroom.id,
    customer: {
      id: customer.id,
      first_name: customer.first_name || '',
      last_name: customer.last_name || '',
      phone_normalized: customer.phone_normalized || '',
      email: customer.email || null,
      customer_type: (customer.customer_type || 'homeowner') as 'homeowner' | 'contractor',
      address_line1: customer.address_line1 || null,
      city: customer.city || null,
      state: customer.state || null,
      zip_code: customer.zip_code || null,
    },
    end_client: { first_name: null, last_name: null, phone: null, email: null, address: null },
    project: {
      name: project.project_name || '',
      reference_number: project.reference_number || '',
      notes: project.project_notes || null,
      status: project.status || 'submitted',
      submitted_at: project.submitted_at || new Date().toISOString(),
    },
    showroom: {
      name: showroom.name || '',
      phone: showroom.phone || null,
      email: showroom.email || null,
      address_line1: showroom.address_line1 || null,
      city: showroom.city || null,
      state: showroom.state || null,
      postal_code: showroom.postal_code || null,
      showroom_code: showroom.showroom_code || '',
    },
    triggered_by: 'webhook',
    _log: log,
    _schedulingLink: null as string | null,
  }
}

/**
 * Process a post-call flow starting from an outcome node.
 * Executes immediate actions (SMS, SendLink) and sets up waits.
 */
async function processPostCallFlow(
  logId: string,
  outcome: SimplifiedOutcome,
  flow: PostCallFlow
) {
  console.log('[VOICE_WEBHOOK] Processing post-call flow for outcome:', outcome)

  // Find the outcome node matching this call result
  const outcomeNode = flow.nodes.find(
    (n) => n.type === 'outcome' && n.data.outcome === outcome
  )
  if (!outcomeNode) {
    console.log('[VOICE_WEBHOOK] No outcome node found for:', outcome)
    await supabaseAdmin
      .from('voice_agent_logs')
      .update({ flow_status: 'completed' })
      .eq('id', logId)
    return
  }

  // Follow the edge from the outcome node
  let currentNode = findNextNode(flow, outcomeNode.id)
  if (!currentNode) {
    console.log('[VOICE_WEBHOOK] No next node after outcome, completing flow')
    await supabaseAdmin
      .from('voice_agent_logs')
      .update({ flow_status: 'completed' })
      .eq('id', logId)
    return
  }

  // Rebuild payload for template interpolation
  const payloadData = await rebuildPayloadFromLog(logId)

  // Fetch scheduling link
  const { data: log } = await supabaseAdmin
    .from('voice_agent_logs')
    .select('showroom_id')
    .eq('id', logId)
    .single()

  let schedulingLink: string | null = null
  if (log) {
    const { data: vaSettings } = await supabaseAdmin
      .from('voice_agent_showroom_settings')
      .select('scheduling_link')
      .eq('showroom_id', log.showroom_id)
      .single()
    schedulingLink = vaSettings?.scheduling_link || null
  }

  // Traverse the flow
  while (currentNode) {
    console.log('[VOICE_WEBHOOK] Processing node:', currentNode.id, currentNode.type)

    switch (currentNode.type) {
      case 'stop': {
        await supabaseAdmin
          .from('voice_agent_logs')
          .update({ flow_status: 'completed', flow_current_node: currentNode.id })
          .eq('id', logId)
        return
      }

      case 'wait': {
        const mode = (currentNode.data.mode as string) || 'hours'
        let nextAt: Date

        if (mode === 'next_business_day') {
          // Fetch showroom timezone
          const { data: log } = await supabaseAdmin
            .from('voice_agent_logs')
            .select('showroom_id')
            .eq('id', logId)
            .single()
          const { data: showroom } = await supabaseAdmin
            .from('showrooms')
            .select('timezone')
            .eq('id', log?.showroom_id)
            .single()
          const tz = showroom?.timezone || 'America/New_York'
          const { getNextBusinessDayTime } = await import('../_shared/voice-agent/business-hours.ts')
          nextAt = getNextBusinessDayTime(tz)
        } else {
          const hours = (currentNode.data.hours as number) || 1
          nextAt = new Date()
          nextAt.setHours(nextAt.getHours() + hours)
        }

        await supabaseAdmin
          .from('voice_agent_logs')
          .update({
            flow_status: 'waiting',
            flow_current_node: currentNode.id,
            flow_next_at: nextAt.toISOString(),
          })
          .eq('id', logId)
        return
      }

      case 'sms': {
        if (payloadData) {
          const templateVars = buildTemplateVariables(payloadData)
          if (schedulingLink) {
            templateVars.scheduling_link = schedulingLink
          }
          const smsBody = interpolate(
            (currentNode.data.template as string) || '',
            templateVars
          )
          const smsResult = await sendSms({
            to: payloadData.customer.phone_normalized,
            body: smsBody,
          })
          console.log('[VOICE_WEBHOOK] Flow SMS sent:', smsResult.success)
        }
        // Continue to next node
        currentNode = findNextNode(flow, currentNode.id)
        break
      }

      case 'retry_call': {
        // Set flow_status to waiting with immediate next_at (cron picks up)
        await supabaseAdmin
          .from('voice_agent_logs')
          .update({
            flow_status: 'waiting',
            flow_current_node: currentNode.id,
            flow_next_at: new Date().toISOString(),
          })
          .eq('id', logId)
        return
      }

      default: {
        // Unknown node type, try to continue
        currentNode = findNextNode(flow, currentNode.id)
        break
      }
    }
  }

  // No more nodes, complete the flow
  await supabaseAdmin
    .from('voice_agent_logs')
    .update({ flow_status: 'completed' })
    .eq('id', logId)
}

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
    const event = await req.json()
    console.log('[VOICE_WEBHOOK] Received Vapi event', {
      type: event.message?.type || event.type,
      callId: event.message?.call?.id || event.call?.id,
    })

    const eventType = event.message?.type || event.type
    const callId = event.message?.call?.id || event.call?.id

    if (!callId) {
      console.log('[VOICE_WEBHOOK] No call ID in event, ignoring')
      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Handle call-started or status-update with in-progress
    if (
      eventType === 'call-started' ||
      eventType === 'status-update' && (event.message?.status === 'in-progress' || event.status === 'in-progress')
    ) {
      console.log('[VOICE_WEBHOOK] Call started/in-progress:', callId)
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({
          call_status: 'in-progress',
          call_started_at: new Date().toISOString(),
        })
        .eq('vapi_call_id', callId)

      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Handle end-of-call-report
    if (eventType === 'end-of-call-report') {
      const report = event.message || event
      console.log('[VOICE_WEBHOOK] End of call report for:', callId)

      // Find log by vapi_call_id
      const { data: log, error: logError } = await supabaseAdmin
        .from('voice_agent_logs')
        .select('*')
        .eq('vapi_call_id', callId)
        .single()

      if (logError || !log) {
        console.error('[VOICE_WEBHOOK] Log not found for call:', callId)
        return new Response(
          JSON.stringify({ success: false, message: 'Log not found' }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Extract data from report — Vapi nests data under `artifact`
      const endedReason = report.endedReason || report.call?.endedReason || 'unknown-error'
      const summary = report.analysis?.summary || report.summary || report.artifact?.summary || null
      const recordingUrl = report.artifact?.recordingUrl || report.recordingUrl || null

      // Transcript: Vapi puts messages in artifact.messages or report.messages
      const messages = report.artifact?.messages || report.messages || report.transcript || []
      const transcript = Array.isArray(messages)
        ? messages
            .filter((m: any) => m.role && m.content)
            .map((m: any) => `${m.role}: ${m.content}`)
            .join('\n')
        : typeof messages === 'string'
        ? messages
        : null

      console.log('[VOICE_WEBHOOK] Extracted data', {
        endedReason,
        hasSummary: !!summary,
        hasTranscript: !!transcript,
        transcriptLength: transcript?.length || 0,
        hasRecording: !!recordingUrl,
      })

      // Calculate duration
      let durationSeconds: number | null = null
      const startedAt = report.startedAt || report.call?.startedAt
      const endedAt = report.endedAt || report.call?.endedAt
      if (startedAt && endedAt) {
        durationSeconds = Math.round(
          (new Date(endedAt).getTime() - new Date(startedAt).getTime()) / 1000
        )
      }

      // Map outcome
      let outcome: SimplifiedOutcome = mapVapiOutcome(endedReason)

      // Special case refinements
      if (outcome === 'not_interested' && durationSeconds !== null && durationSeconds < 10) {
        outcome = 'hung_up_early'
      }

      // Check transcript and summary for positive signals
      const transcriptLower = (transcript || '').toLowerCase()
      const summaryLower = (summary || '').toLowerCase()
      const combinedText = transcriptLower + ' ' + summaryLower

      // Check if link was sent during call
      if (combinedText.includes('scheduling link') || combinedText.includes('send_scheduling_link') || combinedText.includes('booking link')) {
        outcome = 'link_sent'
      }

      // Check for successful appointment/scheduling
      if (
        combinedText.includes('scheduled') ||
        combinedText.includes('appointment') ||
        combinedText.includes('booked') ||
        combinedText.includes('pre-measurement')
      ) {
        outcome = 'interested'
      }

      // Check for callback requests
      if (
        combinedText.includes('call me back') ||
        combinedText.includes('callback') ||
        combinedText.includes('call back later')
      ) {
        outcome = 'callback_requested'
      }

      // Update log with all call data
      const updateData: Record<string, unknown> = {
        vapi_ended_reason: endedReason,
        call_summary: summary,
        call_transcript: transcript,
        call_duration_seconds: durationSeconds,
        call_ended_at: endedAt || new Date().toISOString(),
        call_status: 'completed',
        outcome,
        outcome_details: {
          raw_ended_reason: endedReason,
          duration_seconds: durationSeconds,
          had_transcript: !!transcript,
          has_recording: !!recordingUrl,
        },
      }

      await supabaseAdmin
        .from('voice_agent_logs')
        .update(updateData)
        .eq('id', log.id)

      console.log('[VOICE_WEBHOOK] Updated log with outcome:', outcome)

      // Download recording from Vapi and upload to Supabase Storage (async, non-blocking)
      if (recordingUrl) {
        (async () => {
          try {
            console.log('[VOICE_WEBHOOK] Downloading recording from Vapi:', recordingUrl)
            const recordingRes = await fetch(recordingUrl)
            if (!recordingRes.ok) {
              console.error('[VOICE_WEBHOOK] Failed to download recording:', recordingRes.status)
              return
            }

            const audioBlob = await recordingRes.arrayBuffer()
            const contentType = recordingRes.headers.get('content-type') || 'audio/mpeg'
            const ext = contentType.includes('wav') ? 'wav' : contentType.includes('ogg') ? 'ogg' : 'mp3'
            const storagePath = `${log.showroom_id}/${log.id}.${ext}`

            const { error: uploadError } = await supabaseAdmin.storage
              .from('recordings')
              .upload(storagePath, audioBlob, {
                contentType,
                upsert: true,
              })

            if (uploadError) {
              console.error('[VOICE_WEBHOOK] Recording upload failed:', uploadError)
              return
            }

            // Store the storage path (frontend will create signed URLs via RLS)
            await supabaseAdmin
              .from('voice_agent_logs')
              .update({ recording_url: storagePath })
              .eq('id', log.id)

            console.log('[VOICE_WEBHOOK] Recording saved to storage:', storagePath)
          } catch (err) {
            console.error('[VOICE_WEBHOOK] Recording save error:', err)
          }
        })()
      }

      // Start post-call flow
      const { data: vaSettings } = await supabaseAdmin
        .from('voice_agent_showroom_settings')
        .select('post_call_flow')
        .eq('showroom_id', log.showroom_id)
        .single()

      const flow: PostCallFlow = (vaSettings?.post_call_flow as PostCallFlow) || DEFAULT_POST_CALL_FLOW

      await processPostCallFlow(log.id, outcome, flow)

      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // For other event types, just acknowledge
    console.log('[VOICE_WEBHOOK] Unhandled event type:', eventType)
    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[VOICE_WEBHOOK] Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
