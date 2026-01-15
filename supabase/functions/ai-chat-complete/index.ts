import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import OpenAI from 'https://esm.sh/openai@4.52.0'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!
const OPENAI_MODEL = Deno.env.get('OPENAI_MODEL') || 'gpt-4o-mini'

const openai = new OpenAI({ apiKey: OPENAI_API_KEY })

interface CompleteRequest {
  conversation_id: string
}

// Call webhook with conversation summary
async function callConversationWebhook(
  webhookUrl: string,
  payload: Record<string, unknown>,
  projectId: string
): Promise<void> {
  console.log(`[WEBHOOK] Calling conversation webhook: ${webhookUrl}`)
  console.log(`[WEBHOOK] Project ID: ${projectId}`)

  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 10000) // 10 second timeout

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'NextLean-Scan-Webhook/1.0',
        'X-Webhook-Event': 'conversation.completed',
        'X-Project-ID': projectId,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    if (!response.ok) {
      const responseText = await response.text()
      console.error(`[WEBHOOK] Webhook returned status ${response.status}`)
      console.error(`[WEBHOOK] Response body: ${responseText}`)
    } else {
      console.log(`[WEBHOOK] ✅ Conversation webhook called successfully for project ${projectId}`)
    }
  } catch (err: any) {
    clearTimeout(timeoutId)
    console.error(`[WEBHOOK] ❌ Conversation webhook failed:`, err.message)
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body: CompleteRequest = await req.json()
    const { conversation_id } = body

    if (!conversation_id) {
      return new Response(
        JSON.stringify({ error: 'conversation_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Get conversation with messages
    const { data: conversation, error: convError } = await supabaseAdmin
      .from('ai_chat_conversations')
      .select('id, thread_id, assistant_id, status, project_id')
      .eq('id', conversation_id)
      .single()

    if (convError || !conversation) {
      return new Response(
        JSON.stringify({ error: 'Conversation not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Already completed
    if (conversation.status === 'completed') {
      return new Response(
        JSON.stringify({ success: true, already_completed: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Mark conversation as completed immediately (fast response to user)
    const { error: updateError } = await supabaseAdmin
      .from('ai_chat_conversations')
      .update({
        status: 'completed',
        summary: 'Generating summary...', // Placeholder, will be updated async
        completed_at: new Date().toISOString(),
      })
      .eq('id', conversation_id)

    if (updateError) {
      throw new Error(`Failed to update conversation: ${updateError.message}`)
    }

    // 3. Generate summary and call webhook in background (non-blocking)
    const generateSummaryAndNotify = async () => {
      try {
        const { data: messages } = await supabaseAdmin
          .from('ai_chat_messages')
          .select('role, content')
          .eq('conversation_id', conversation_id)
          .order('created_at', { ascending: true })

        let summary = 'No conversation recorded.'

        if (messages && messages.length > 0) {
          const conversationText = messages
            .map((m: { role: string; content: string }) => `${m.role === 'assistant' ? 'Assistant' : 'Customer'}: ${m.content}`)
            .join('\n\n')

          const summaryResponse = await openai.chat.completions.create({
            model: OPENAI_MODEL,
            messages: [
              {
                role: 'system',
                content: `You are summarizing a design consultation conversation between a customer and an AI design assistant.
Create a concise summary (3-5 bullet points) highlighting:
- Customer's style preferences
- Color/material preferences
- Timeline or urgency
- Budget considerations (if mentioned)
- Any special requirements or requests
- Overall design vision

Be specific and actionable for the showroom team. Use bullet points.`
              },
              {
                role: 'user',
                content: `Please summarize this conversation:\n\n${conversationText}`
              }
            ],
            max_tokens: 500,
            temperature: 0.3,
          })

          summary = summaryResponse.choices[0]?.message?.content || 'Unable to generate summary.'
        }

        // Update with actual summary
        await supabaseAdmin
          .from('ai_chat_conversations')
          .update({ summary })
          .eq('id', conversation_id)

        console.log(`[SUMMARY] Generated summary for conversation ${conversation_id}`)

        // Get project and showroom details for webhook
        const { data: project } = await supabaseAdmin
          .from('projects')
          .select(`
            id,
            reference_number,
            customer_first_name,
            customer_last_name,
            customer_email,
            customer_phone,
            project_name,
            showroom_id,
            showrooms (
              id,
              name,
              showroom_code,
              webhook_url,
              notification_emails,
              phone,
              email
            )
          `)
          .eq('id', conversation.project_id)
          .single()

        // Call webhook if configured
        if (project?.showrooms?.webhook_url) {
          const showroom = project.showrooms as any
          const webhookPayload = {
            event: 'conversation.completed',
            timestamp: new Date().toISOString(),
            project: {
              id: project.id,
              reference_number: project.reference_number,
              name: project.project_name,
            },
            customer: {
              first_name: project.customer_first_name,
              last_name: project.customer_last_name,
              email: project.customer_email,
              phone: project.customer_phone,
            },
            conversation: {
              id: conversation_id,
              message_count: messages?.length || 0,
              summary: summary,
              completed_at: new Date().toISOString(),
            },
            showroom: {
              id: showroom.id,
              name: showroom.name,
              code: showroom.showroom_code,
              phone: showroom.phone || null,
              email: showroom.email || null,
              notification_emails: showroom.notification_emails
                ? showroom.notification_emails.split(',').map((e: string) => e.trim()).filter((e: string) => e.length > 0)
                : [],
            },
          }

          await callConversationWebhook(showroom.webhook_url, webhookPayload, project.id)
        }
      } catch (err) {
        console.error(`[SUMMARY] Failed to generate summary or call webhook:`, err)
      }
    }

    // Fire and forget - don't await
    generateSummaryAndNotify()

    return new Response(
      JSON.stringify({ success: true, summary: 'Generating summary...' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error completing conversation:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
