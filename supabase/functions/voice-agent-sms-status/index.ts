// Twilio SMS StatusCallback handler
// Twilio POSTs delivery status updates here (queued → sent → delivered / undelivered / failed)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

// Twilio error code descriptions for common failures
const TWILIO_ERROR_DESCRIPTIONS: Record<string, string> = {
  '30001': 'Queue overflow',
  '30002': 'Account suspended',
  '30003': 'Unreachable destination handset',
  '30004': 'Message blocked',
  '30005': 'Unknown destination handset',
  '30006': 'Landline or unreachable carrier',
  '30007': 'Carrier violation',
  '30008': 'Unknown error',
  '30034': 'Blocked by carrier (10DLC registration required)',
  '30035': 'Blocked by carrier (messaging service required)',
  '21610': 'Recipient unsubscribed (STOP)',
  '21614': 'Invalid mobile number',
  '21211': 'Invalid phone number',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Twilio sends as application/x-www-form-urlencoded
    const formData = await req.formData()
    const messageSid = formData.get('MessageSid') as string
    const messageStatus = formData.get('MessageStatus') as string
    const errorCode = formData.get('ErrorCode') as string | null

    console.log('[SMS_STATUS] Received:', { messageSid, messageStatus, errorCode })

    if (!messageSid || !messageStatus) {
      return new Response('OK', { status: 200 })
    }

    // Find the log entry by sms_sid
    const { data: log } = await supabaseAdmin
      .from('voice_agent_logs')
      .select('id, sms_status')
      .eq('sms_sid', messageSid)
      .single()

    if (!log) {
      console.log('[SMS_STATUS] No log found for SID:', messageSid)
      return new Response('OK', { status: 200 })
    }

    // Map Twilio status to our status
    // Twilio statuses: queued → sending → sent → delivered / undelivered / failed
    let newStatus: string
    let smsError: string | null = null

    switch (messageStatus) {
      case 'delivered':
        newStatus = 'delivered'
        break
      case 'sent':
        newStatus = 'sent'
        break
      case 'undelivered':
      case 'failed': {
        newStatus = 'failed'
        const desc = errorCode ? TWILIO_ERROR_DESCRIPTIONS[errorCode] : null
        smsError = desc
          ? `${desc} (Twilio error ${errorCode})`
          : errorCode
            ? `Twilio error ${errorCode}`
            : `Message ${messageStatus}`
        break
      }
      default:
        // queued, sending, etc. — don't downgrade status
        console.log('[SMS_STATUS] Intermediate status, skipping:', messageStatus)
        return new Response('OK', { status: 200 })
    }

    // Don't downgrade: if already 'delivered', don't overwrite
    if (log.sms_status === 'delivered') {
      return new Response('OK', { status: 200 })
    }

    const updateData: Record<string, unknown> = { sms_status: newStatus }
    if (smsError) updateData.sms_error = smsError

    await supabaseAdmin
      .from('voice_agent_logs')
      .update(updateData)
      .eq('id', log.id)

    console.log(`[SMS_STATUS] Updated log ${log.id}: ${newStatus}${smsError ? ` (${smsError})` : ''}`)

    return new Response('OK', { status: 200 })
  } catch (err) {
    console.error('[SMS_STATUS] Error:', err)
    return new Response('OK', { status: 200 }) // Always 200 for Twilio
  }
})
