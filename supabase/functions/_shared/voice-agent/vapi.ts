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

    if (!vapiPhoneNumberId) {
      console.error('[VOICE_CALL] vapi_phone_number_id not configured in platform_settings')
      return { success: false, error: 'Vapi phone number ID not configured' }
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serverUrl = supabaseUrl
      ? `${supabaseUrl}/functions/v1/voice-agent-webhook`
      : ''

    const requestBody: Record<string, unknown> = {
      phoneNumberId: vapiPhoneNumberId,
      customer: {
        number: customerPhone,
      },
      assistant: {
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
        tools: tools || [],
      },
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
