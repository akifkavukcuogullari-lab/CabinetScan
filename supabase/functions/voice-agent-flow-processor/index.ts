// Voice Agent Flow Processor — Cron-triggered Edge Function
// Runs every 15 minutes to process waiting flow nodes (retries, scheduled SMS, etc.)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import type { PostCallFlow, FlowNode, VoiceAgentTriggerPayload } from '../_shared/voice-agent/types.ts'
import { DEFAULT_POST_CALL_FLOW } from '../_shared/voice-agent/constants.ts'
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
 * Rebuild trigger payload from database records.
 */
async function rebuildPayload(log: any): Promise<VoiceAgentTriggerPayload | null> {
  const { data: project } = await supabaseAdmin
    .from('projects')
    .select('id, project_name, reference_number, project_notes, status, submitted_at')
    .eq('id', log.project_id)
    .single()

  const { data: customer } = await supabaseAdmin
    .from('customers')
    .select('id, first_name, last_name, phone_normalized, email, customer_type, address_line1, city, state, zip_code')
    .eq('id', log.customer_id)
    .single()

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
    triggered_by: `flow-processor-${log.id}`,
  }
}

/**
 * Process a single waiting log entry through its flow.
 */
async function processLog(log: any): Promise<{ success: boolean; error?: string }> {
  try {
    const currentNodeId = log.flow_current_node
    if (!currentNodeId) {
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({ flow_status: 'completed' })
        .eq('id', log.id)
      return { success: true }
    }

    // Get the showroom's post_call_flow
    const { data: vaSettings } = await supabaseAdmin
      .from('voice_agent_showroom_settings')
      .select('post_call_flow, scheduling_link')
      .eq('showroom_id', log.showroom_id)
      .single()

    const flow: PostCallFlow = (vaSettings?.post_call_flow as PostCallFlow) || DEFAULT_POST_CALL_FLOW
    const schedulingLink = vaSettings?.scheduling_link || null

    // Find the current node
    const currentNode = flow.nodes.find((n) => n.id === currentNodeId)
    if (!currentNode) {
      console.error('[FLOW_PROCESSOR] Current node not found:', currentNodeId, 'for log:', log.id)
      await supabaseAdmin
        .from('voice_agent_logs')
        .update({ flow_status: 'completed' })
        .eq('id', log.id)
      return { success: true }
    }

    // Rebuild payload for template interpolation
    const payload = await rebuildPayload(log)

    // Process based on current node type
    let nextNode: FlowNode | null = null

    switch (currentNode.type) {
      case 'wait': {
        // Wait period has elapsed (cron picked it up), move to next node
        nextNode = findNextNode(flow, currentNode.id)
        break
      }

      case 'retry_call': {
        const maxAttempts = (currentNode.data.maxAttempts as number) || 3

        // Count existing attempts for this project
        const { count: totalAttempts } = await supabaseAdmin
          .from('voice_agent_logs')
          .select('id', { count: 'exact', head: true })
          .eq('project_id', log.project_id)

        const attemptCount = totalAttempts || 0

        if (attemptCount < maxAttempts) {
          // Trigger a new call via voice-agent-trigger
          if (payload) {
            console.log('[FLOW_PROCESSOR] Triggering retry call, attempt', attemptCount + 1, 'of', maxAttempts)
            const supabaseUrl = Deno.env.get('SUPABASE_URL')
            const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

            try {
              await fetch(`${supabaseUrl}/functions/v1/voice-agent-trigger`, {
                method: 'POST',
                headers: {
                  'Authorization': `Bearer ${serviceRoleKey}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify(payload),
              })
            } catch (err) {
              console.error('[FLOW_PROCESSOR] Failed to trigger retry call:', err)
            }
          }

          // Mark this log as completed (new log will be created by the trigger)
          await supabaseAdmin
            .from('voice_agent_logs')
            .update({ flow_status: 'completed', flow_current_node: currentNode.id })
            .eq('id', log.id)
          return { success: true }
        } else {
          // Max attempts reached, follow the max_reached edge
          console.log('[FLOW_PROCESSOR] Max attempts reached:', attemptCount, '>=', maxAttempts)
          nextNode = findNextNode(flow, currentNode.id, 'max_reached')
          break
        }
      }

      case 'sms': {
        if (payload) {
          const templateVars = buildTemplateVariables(payload)
          if (schedulingLink) {
            templateVars.scheduling_link = schedulingLink
          }
          const smsBody = interpolate(
            (currentNode.data.template as string) || '',
            templateVars
          )
          const smsResult = await sendSms({
            to: payload.customer.phone_normalized,
            body: smsBody,
          })
          console.log('[FLOW_PROCESSOR] Flow SMS sent:', smsResult.success)
        }
        nextNode = findNextNode(flow, currentNode.id)
        break
      }

      case 'send_link': {
        if (payload && schedulingLink) {
          const smsBody = `Here's your link to schedule a visit: ${schedulingLink}`
          await sendSms({
            to: payload.customer.phone_normalized,
            body: smsBody,
          })
          console.log('[FLOW_PROCESSOR] Scheduling link sent')
        }
        nextNode = findNextNode(flow, currentNode.id)
        break
      }

      case 'condition': {
        // Evaluate condition and follow the appropriate edge
        // For now, follow the default (no sourceHandle) edge
        nextNode = findNextNode(flow, currentNode.id)
        break
      }

      case 'stop': {
        await supabaseAdmin
          .from('voice_agent_logs')
          .update({ flow_status: 'completed', flow_current_node: currentNode.id })
          .eq('id', log.id)
        return { success: true }
      }

      default: {
        nextNode = findNextNode(flow, currentNode.id)
        break
      }
    }

    // Process the next node(s) in a loop (for immediate actions like SMS chains)
    while (nextNode) {
      console.log('[FLOW_PROCESSOR] Processing next node:', nextNode.id, nextNode.type)

      switch (nextNode.type) {
        case 'stop': {
          await supabaseAdmin
            .from('voice_agent_logs')
            .update({ flow_status: 'completed', flow_current_node: nextNode.id })
            .eq('id', log.id)
          return { success: true }
        }

        case 'wait': {
          const hours = (nextNode.data.hours as number) || 1
          const nextAt = new Date()
          nextAt.setHours(nextAt.getHours() + hours)

          await supabaseAdmin
            .from('voice_agent_logs')
            .update({
              flow_status: 'waiting',
              flow_current_node: nextNode.id,
              flow_next_at: nextAt.toISOString(),
            })
            .eq('id', log.id)
          return { success: true }
        }

        case 'sms': {
          if (payload) {
            const templateVars = buildTemplateVariables(payload)
            if (schedulingLink) {
              templateVars.scheduling_link = schedulingLink
            }
            const smsBody = interpolate(
              (nextNode.data.template as string) || '',
              templateVars
            )
            await sendSms({
              to: payload.customer.phone_normalized,
              body: smsBody,
            })
          }
          nextNode = findNextNode(flow, nextNode.id)
          break
        }

        case 'send_link': {
          if (payload && schedulingLink) {
            const smsBody = `Here's your link to schedule a visit: ${schedulingLink}`
            await sendSms({
              to: payload.customer.phone_normalized,
              body: smsBody,
            })
          }
          nextNode = findNextNode(flow, nextNode.id)
          break
        }

        case 'retry_call': {
          // Set waiting with immediate processing
          await supabaseAdmin
            .from('voice_agent_logs')
            .update({
              flow_status: 'waiting',
              flow_current_node: nextNode.id,
              flow_next_at: new Date().toISOString(),
            })
            .eq('id', log.id)
          return { success: true }
        }

        default: {
          nextNode = findNextNode(flow, nextNode.id)
          break
        }
      }
    }

    // No more nodes
    await supabaseAdmin
      .from('voice_agent_logs')
      .update({ flow_status: 'completed' })
      .eq('id', log.id)
    return { success: true }
  } catch (error) {
    console.error('[FLOW_PROCESSOR] Error processing log:', log.id, error)
    return { success: false, error: String(error) }
  }
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
    // Auth check: verify the request comes from a trusted source (service role key)
    const authHeader = req.headers.get('Authorization')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !authHeader.includes(serviceRoleKey || '')) {
      console.error('[FLOW_PROCESSOR] Unauthorized request')
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Query waiting logs that are ready to process
    const { data: waitingLogs, error: queryError } = await supabaseAdmin
      .from('voice_agent_logs')
      .select('*')
      .eq('flow_status', 'waiting')
      .lte('flow_next_at', new Date().toISOString())
      .order('flow_next_at', { ascending: true })
      .limit(50)

    if (queryError) {
      console.error('[FLOW_PROCESSOR] Error querying waiting logs:', queryError)
      return new Response(
        JSON.stringify({ error: 'Failed to query waiting logs' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!waitingLogs || waitingLogs.length === 0) {
      console.log('[FLOW_PROCESSOR] No waiting logs to process')
      return new Response(
        JSON.stringify({ success: true, processed: 0, errors: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('[FLOW_PROCESSOR] Processing', waitingLogs.length, 'waiting logs')

    let processed = 0
    let errors = 0

    for (const log of waitingLogs) {
      const result = await processLog(log)
      if (result.success) {
        processed++
      } else {
        errors++
        console.error('[FLOW_PROCESSOR] Failed to process log:', log.id, result.error)
      }
    }

    console.log('[FLOW_PROCESSOR] Complete', { processed, errors })

    return new Response(
      JSON.stringify({ success: true, processed, errors }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[FLOW_PROCESSOR] Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
