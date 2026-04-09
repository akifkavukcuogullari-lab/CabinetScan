// Voice Agent Send Link — Vapi tool webhook Edge Function
// Called mid-conversation when the AI assistant invokes the send_scheduling_link tool.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendSms } from '../_shared/voice-agent/twilio.ts'

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
    const body = await req.json()
    console.log('[VOICE_SEND_LINK] Received tool call request')

    // Extract call ID and tool call ID from Vapi tool call format
    // Vapi sends: { message: { type: "tool-calls", call: { id }, toolCallList: [{ id, function: { name, arguments } }] } }
    const message = body.message || body
    const callId = message.call?.id || body.call?.id
    const toolCalls = message.toolCallList || message.toolCalls || []
    const toolCall = toolCalls.find(
      (tc: any) => tc.function?.name === 'send_scheduling_link'
    ) || toolCalls[0]
    const toolCallId = toolCall?.id

    console.log('[VOICE_SEND_LINK] Call ID:', callId, 'Tool Call ID:', toolCallId)

    if (!callId) {
      console.error('[VOICE_SEND_LINK] No call ID found in request')
      return new Response(
        JSON.stringify({
          results: [
            {
              toolCallId: toolCallId || 'unknown',
              result: 'Error: Could not identify the call',
            },
          ],
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up voice_agent_logs by vapi_call_id
    const { data: log, error: logError } = await supabaseAdmin
      .from('voice_agent_logs')
      .select('id, showroom_id, customer_phone')
      .eq('vapi_call_id', callId)
      .single()

    if (logError || !log) {
      console.error('[VOICE_SEND_LINK] Log not found for call:', callId)
      return new Response(
        JSON.stringify({
          results: [
            {
              toolCallId: toolCallId || 'unknown',
              result: 'Error: Could not find call record',
            },
          ],
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get showroom's scheduling_link
    const { data: vaSettings } = await supabaseAdmin
      .from('voice_agent_showroom_settings')
      .select('scheduling_link')
      .eq('showroom_id', log.showroom_id)
      .single()

    const schedulingLink = vaSettings?.scheduling_link

    if (!schedulingLink) {
      console.error('[VOICE_SEND_LINK] No scheduling link configured for showroom:', log.showroom_id)
      return new Response(
        JSON.stringify({
          results: [
            {
              toolCallId: toolCallId || 'unknown',
              result: 'Sorry, no scheduling link is configured for this showroom. Please ask the customer to call the showroom directly.',
            },
          ],
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!log.customer_phone) {
      console.error('[VOICE_SEND_LINK] No customer phone on log:', log.id)
      return new Response(
        JSON.stringify({
          results: [
            {
              toolCallId: toolCallId || 'unknown',
              result: 'Error: No customer phone number available',
            },
          ],
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Send SMS with scheduling link
    const smsBody = `Here's your link to schedule a visit: ${schedulingLink}`
    const smsResult = await sendSms({
      to: log.customer_phone,
      body: smsBody,
    })

    // Update log to mark that link was sent
    await supabaseAdmin
      .from('voice_agent_logs')
      .update({
        outcome_details: {
          ...(log as any).outcome_details,
          link_sent_during_call: true,
          link_sent_at: new Date().toISOString(),
          link_sms_sid: smsResult.sid || null,
        },
      })
      .eq('id', log.id)

    const resultMessage = smsResult.success
      ? 'Scheduling link sent successfully via SMS'
      : 'Failed to send scheduling link SMS, but please let the customer know they can visit the showroom website'

    console.log('[VOICE_SEND_LINK] Result:', resultMessage)

    return new Response(
      JSON.stringify({
        results: [
          {
            toolCallId: toolCallId || 'unknown',
            result: resultMessage,
          },
        ],
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[VOICE_SEND_LINK] Unexpected error:', error)
    return new Response(
      JSON.stringify({
        results: [
          {
            toolCallId: 'unknown',
            result: 'An error occurred while sending the scheduling link',
          },
        ],
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
