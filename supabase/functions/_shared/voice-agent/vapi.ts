// Vapi outbound call utility for Voice Agent Edge Functions

import { supabaseAdmin } from '../supabase.ts'

interface InitiateCallOptions {
  customerPhone: string
  systemPrompt: string
  firstMessage?: string
  tools?: unknown[]
  scheduledAt?: string
}

interface InitiateCallResult {
  success: boolean
  callId?: string
  error?: string
}

async function getPlatformSetting(key: string): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from('platform_settings')
    .select('value')
    .eq('key', key)
    .single()

  if (error || !data) {
    console.error(`[VOICE_CALL] Failed to read platform_settings key "${key}":`, error?.message)
    return null
  }

  return data.value
}

export async function initiateVapiCall(options: InitiateCallOptions): Promise<InitiateCallResult> {
  const { customerPhone, systemPrompt, firstMessage, tools, scheduledAt } = options

  console.log('[VOICE_CALL] Preparing to initiate Vapi call', {
    customerPhone,
    promptLength: systemPrompt.length,
    hasTools: !!(tools && tools.length),
    scheduled: !!scheduledAt,
  })

  try {
    const [vapiApiKey, vapiPhoneNumberId] = await Promise.all([
      getPlatformSetting('vapi_api_key'),
      getPlatformSetting('vapi_phone_number_id'),
    ])

    if (!vapiApiKey) {
      console.error('[VOICE_CALL] vapi_api_key not configured in platform_settings')
      return { success: false, error: 'Vapi API key not configured' }
    }

    if (!vapiPhoneNumberId || vapiPhoneNumberId.trim().length === 0) {
      console.error('[VOICE_CALL] vapi_phone_number_id not configured in platform_settings')
      return { success: false, error: 'Vapi phone number ID not configured. Set it in Admin → Voice Agent settings.' }
    }

    // Ensure phone number is E.164 format
    let formattedPhone = customerPhone.trim()
    if (!formattedPhone.startsWith('+')) {
      // Assume US number if no country code
      formattedPhone = formattedPhone.replace(/\D/g, '') // strip non-digits
      if (formattedPhone.length === 10) {
        formattedPhone = `+1${formattedPhone}`
      } else if (formattedPhone.length === 11 && formattedPhone.startsWith('1')) {
        formattedPhone = `+${formattedPhone}`
      } else {
        formattedPhone = `+${formattedPhone}`
      }
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serverUrl = supabaseUrl
      ? `${supabaseUrl}/functions/v1/voice-agent-webhook`
      : ''

    const assistantConfig: Record<string, unknown> = {
      model: {
        provider: 'openai',
        model: 'gpt-4o',
        messages: [
          {
            role: 'system',
            content: systemPrompt,
          },
        ],
      },
      voice: {
        provider: '11labs',
        voiceId: '21m00Tcm4TlvDq8ikWAM',
      },
      firstMessage: firstMessage || 'Hi, this is the scheduling assistant. How are you today?',
      serverUrl,
    }

    const requestBody: Record<string, unknown> = {
      phoneNumberId: vapiPhoneNumberId.trim(),
      customer: {
        number: formattedPhone,
      },
      assistant: assistantConfig,
    }

    if (scheduledAt) {
      requestBody.schedulePlan = { earliestAt: scheduledAt }
    }

    console.log('[VOICE_CALL] Sending call request to Vapi API', {
      customerPhone,
      phoneNumberId: vapiPhoneNumberId,
      serverUrl,
    })

    const response = await fetch('https://api.vapi.ai/call', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${vapiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    })

    const data = await response.json()

    console.log('[VOICE_CALL] Vapi API response:', {
      status: response.status,
      callId: data.id,
      error: data.error || data.message,
    })

    if (!response.ok) {
      const errorMessage = data.message || data.error || `Vapi API error (${response.status})`
      console.error('[VOICE_CALL] Vapi error:', JSON.stringify(data))
      return { success: false, error: errorMessage }
    }

    console.log('[VOICE_CALL] Call initiated successfully, ID:', data.id)
    return { success: true, callId: data.id }
  } catch (error) {
    console.error('[VOICE_CALL] Unexpected error initiating call:', error)
    return { success: false, error: `Failed to initiate call: ${error}` }
  }
}
