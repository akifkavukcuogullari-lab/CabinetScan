// Twilio SMS sending utility for Voice Agent Edge Functions

import { supabaseAdmin } from '../supabase.ts'

interface SendSmsOptions {
  to: string
  body: string
  from?: string
}

interface SendSmsResult {
  success: boolean
  sid?: string
  status?: string
  error?: string
  error_code?: number
}

async function getPlatformSetting(key: string): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from('platform_settings')
    .select('value')
    .eq('key', key)
    .single()

  if (error || !data) {
    console.error(`[VOICE_SMS] Failed to read platform_settings key "${key}":`, error?.message)
    return null
  }

  return data.value
}

export async function sendSms({ to, body, from }: SendSmsOptions): Promise<SendSmsResult> {
  console.log('[VOICE_SMS] Preparing to send SMS', { to, bodyLength: body.length })

  try {
    const [accountSid, authToken, defaultFrom] = await Promise.all([
      getPlatformSetting('twilio_account_sid'),
      getPlatformSetting('twilio_auth_token'),
      getPlatformSetting('twilio_phone_number'),
    ])

    if (!accountSid || !authToken) {
      console.error('[VOICE_SMS] Twilio credentials not configured in platform_settings')
      return { success: false, error: 'Twilio credentials not configured' }
    }

    const fromNumber = from || defaultFrom
    if (!fromNumber) {
      console.error('[VOICE_SMS] No "from" phone number provided and twilio_phone_number not set')
      return { success: false, error: 'No sender phone number configured' }
    }

    // Build StatusCallback URL so Twilio notifies us of delivery failures
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
    const statusCallbackUrl = supabaseUrl
      ? `${supabaseUrl}/functions/v1/voice-agent-sms-status`
      : ''

    const params: Record<string, string> = {
      To: to,
      From: fromNumber,
      Body: body,
    }
    if (statusCallbackUrl) {
      params.StatusCallback = statusCallbackUrl
    }

    const formBody = new URLSearchParams(params).toString()

    const credentials = btoa(`${accountSid}:${authToken}`)
    const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`

    console.log('[VOICE_SMS] Sending SMS via Twilio', { to, from: fromNumber })

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: formBody,
    })

    const data = await response.json()

    console.log('[VOICE_SMS] Twilio API response:', {
      status: response.status,
      sid: data.sid,
      msgStatus: data.status,
      errorCode: data.error_code || data.code,
    })

    if (!response.ok || data.code) {
      const errorMessage = data.message || `Twilio API error (${response.status})`
      console.error('[VOICE_SMS] Twilio error:', JSON.stringify(data))
      return { success: false, error: errorMessage, error_code: data.error_code || data.code }
    }

    // Twilio accepted it — status will be 'queued' or 'sent'
    // Actual delivery confirmation comes via StatusCallback
    console.log('[VOICE_SMS] SMS accepted by Twilio, SID:', data.sid, 'status:', data.status)
    return { success: true, sid: data.sid, status: data.status }
  } catch (error) {
    console.error('[VOICE_SMS] Unexpected error sending SMS:', error)
    return { success: false, error: `Failed to send SMS: ${error}` }
  }
}
