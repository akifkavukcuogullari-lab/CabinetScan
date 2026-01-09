import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import OpenAI from 'https://esm.sh/openai@4.52.0'

// Environment variables
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!

// Initialize OpenAI client
const openai = new OpenAI({ apiKey: OPENAI_API_KEY })

interface SendMessageRequest {
  conversation_id: string
  message: string
}

interface SendMessageResponse {
  message_id: string
  content: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse request body
    const body: SendMessageRequest = await req.json()
    const { conversation_id, message } = body

    if (!conversation_id || !message) {
      return new Response(
        JSON.stringify({ error: 'conversation_id and message are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Trim and validate message
    const trimmedMessage = message.trim()
    if (trimmedMessage.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Message cannot be empty' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (trimmedMessage.length > 5000) {
      return new Response(
        JSON.stringify({ error: 'Message too long (max 5000 characters)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Validate conversation exists and get thread_id
    const { data: conversation, error: conversationError } = await supabaseAdmin
      .from('ai_chat_conversations')
      .select('id, thread_id, assistant_id, status, message_count')
      .eq('id', conversation_id)
      .single()

    if (conversationError || !conversation) {
      return new Response(
        JSON.stringify({ error: 'Conversation not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (conversation.status !== 'active') {
      return new Response(
        JSON.stringify({ error: 'Conversation is no longer active' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check message limit (prevent abuse)
    const MAX_MESSAGES = 50
    if (conversation.message_count >= MAX_MESSAGES) {
      return new Response(
        JSON.stringify({ error: 'Maximum message limit reached for this conversation' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Save user message to database
    const { data: userMessageRecord, error: userMsgError } = await supabaseAdmin
      .from('ai_chat_messages')
      .insert({
        conversation_id: conversation_id,
        role: 'user',
        content: trimmedMessage,
      })
      .select('id')
      .single()

    if (userMsgError) {
      throw new Error(`Failed to save user message: ${userMsgError.message}`)
    }

    // 3. Add message to OpenAI thread
    await openai.beta.threads.messages.create(conversation.thread_id, {
      role: 'user',
      content: trimmedMessage,
    })

    // 4. Run assistant on thread
    const run = await openai.beta.threads.runs.createAndPoll(conversation.thread_id, {
      assistant_id: conversation.assistant_id,
    })

    if (run.status !== 'completed') {
      throw new Error(`Assistant run failed with status: ${run.status}`)
    }

    // 5. Get assistant's response
    const messages = await openai.beta.threads.messages.list(conversation.thread_id, {
      order: 'desc',
      limit: 1,
    })

    const assistantMessage = messages.data[0]
    const assistantContent = assistantMessage?.content?.[0]?.type === 'text'
      ? assistantMessage.content[0].text.value
      : 'I apologize, but I had trouble generating a response. Please try again.'

    // 6. Save assistant message to database
    const { data: assistantMessageRecord, error: assistantMsgError } = await supabaseAdmin
      .from('ai_chat_messages')
      .insert({
        conversation_id: conversation_id,
        role: 'assistant',
        content: assistantContent,
      })
      .select('id')
      .single()

    if (assistantMsgError) {
      throw new Error(`Failed to save assistant message: ${assistantMsgError.message}`)
    }

    // 7. Generate summary after every 5 messages (async, don't wait)
    const newMessageCount = conversation.message_count + 2 // user + assistant
    if (newMessageCount % 10 === 0) {
      // Fire and forget - generate summary in background
      generateConversationSummary(conversation_id).catch(console.error)
    }

    // 8. Return response
    return new Response(
      JSON.stringify({
        message_id: assistantMessageRecord.id,
        content: assistantContent,
      } as SendMessageResponse),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error sending message:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

/**
 * Generate a summary of the conversation for showroom owners.
 * Called asynchronously after every 10 messages.
 */
async function generateConversationSummary(conversationId: string): Promise<void> {
  try {
    // Get all messages in the conversation
    const { data: messages } = await supabaseAdmin
      .from('ai_chat_messages')
      .select('role, content, created_at')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true })

    if (!messages || messages.length === 0) return

    // Build conversation transcript
    const transcript = messages
      .map((m) => `${m.role === 'user' ? 'Customer' : 'Assistant'}: ${m.content}`)
      .join('\n\n')

    // Use OpenAI to generate summary
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are a helpful assistant that summarizes customer conversations for cabinet showroom staff.

Create a brief, actionable summary that highlights:
- Customer's design preferences (style, colors, materials)
- Budget range if mentioned
- Timeline if mentioned
- Any specific requirements or concerns
- Key decisions or preferences expressed

Keep the summary under 200 words. Use bullet points. Focus on information useful for the showroom team.`,
        },
        {
          role: 'user',
          content: `Please summarize this customer conversation:\n\n${transcript}`,
        },
      ],
      max_tokens: 500,
    })

    const summary = completion.choices[0]?.message?.content

    if (summary) {
      // Update conversation with summary
      await supabaseAdmin
        .from('ai_chat_conversations')
        .update({ summary })
        .eq('id', conversationId)
    }
  } catch (error) {
    console.error('Error generating conversation summary:', error)
    // Don't throw - this is a background task
  }
}
