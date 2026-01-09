import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import OpenAI from 'https://esm.sh/openai@4.52.0'

// Environment variables
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!
const OPENAI_MODEL = Deno.env.get('OPENAI_MODEL') || 'gpt-4o-mini'

// Initialize OpenAI client
const openai = new OpenAI({ apiKey: OPENAI_API_KEY })

interface StartChatRequest {
  project_id: string
  reference_number: string
}

interface StartChatResponse {
  conversation_id: string
  thread_id: string
  greeting: string
  assistant_name: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse request body
    const body: StartChatRequest = await req.json()
    const { project_id, reference_number } = body

    if (!project_id || !reference_number) {
      return new Response(
        JSON.stringify({ error: 'project_id and reference_number are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Validate project exists with matching reference number
    console.log('Looking up project:', { project_id, reference_number })

    const { data: project, error: projectError } = await supabaseAdmin
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
        webhook_payload,
        created_at,
        showrooms!inner (
          id,
          name,
          showroom_code,
          ai_chatbot_enabled,
          ai_assistant_name,
          ai_assistant_avatar_url,
          subscription_status,
          subscription_plans (
            slug,
            has_ai_agent
          )
        )
      `)
      .eq('id', project_id)
      .eq('reference_number', reference_number)
      .single()

    console.log('Project query result:', { project, projectError })

    if (projectError || !project) {
      console.error('Project not found:', { projectError, project_id, reference_number })
      return new Response(
        JSON.stringify({
          error: 'Project not found or invalid reference number',
          details: projectError?.message || 'No project data returned'
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const showroom = project.showrooms as any

    // 2. Check if AI chatbot is enabled for this showroom
    if (!showroom.ai_chatbot_enabled) {
      return new Response(
        JSON.stringify({ error: 'AI chatbot is not enabled for this showroom' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. Check subscription plan has AI agent access (Business+)
    const plan = showroom.subscription_plans as any
    const isTrialWithProFeatures = showroom.subscription_status === 'trial' && !plan
    const hasAiAgent = plan?.has_ai_agent || isTrialWithProFeatures

    if (!hasAiAgent) {
      return new Response(
        JSON.stringify({ error: 'AI agent feature requires Business plan or higher' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. Check if conversation already exists for this project
    const { data: existingConversation } = await supabaseAdmin
      .from('ai_chat_conversations')
      .select('id, thread_id, status')
      .eq('project_id', project_id)
      .single()

    if (existingConversation) {
      // If conversation is completed, don't allow reopening
      if (existingConversation.status === 'completed') {
        return new Response(
          JSON.stringify({
            error: 'Chat conversation has already been completed',
            completed: true
          }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Return existing active conversation - fetch first assistant message as greeting
      const { data: firstMessage } = await supabaseAdmin
        .from('ai_chat_messages')
        .select('content')
        .eq('conversation_id', existingConversation.id)
        .eq('role', 'assistant')
        .order('created_at', { ascending: true })
        .limit(1)
        .single()

      return new Response(
        JSON.stringify({
          conversation_id: existingConversation.id,
          thread_id: existingConversation.thread_id,
          greeting: firstMessage?.content || 'Hello! How can I help you today?',
          assistant_name: showroom.ai_assistant_name || 'Design Assistant',
        } as StartChatResponse),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. Get project measurements
    const { data: measurements } = await supabaseAdmin
      .from('project_measurements')
      .select('*')
      .eq('project_id', project_id)
      .single()

    // 6. Get product selections
    const { data: selections } = await supabaseAdmin
      .from('project_selections')
      .select(`
        quantity,
        products (
          name,
          categories (name)
        )
      `)
      .eq('project_id', project_id)

    // 7. Get system prompt for this showroom
    const { data: systemPromptData } = await supabaseAdmin
      .rpc('get_ai_system_prompt', { p_showroom_id: showroom.id })

    const systemPromptTemplate = systemPromptData || getDefaultSystemPrompt()

    // Replace variables in system prompt
    const customerName = `${project.customer_first_name || ''} ${project.customer_last_name || ''}`.trim() || 'Customer'
    const systemPrompt = systemPromptTemplate
      .replace(/\{showroom_name\}/g, showroom.name)
      .replace(/\{customer_name\}/g, customerName)

    // 8. Build project context for AI
    const projectContext = buildProjectContext(project, measurements, selections)

    // 9. Create OpenAI Assistant
    const assistantName = showroom.ai_assistant_name || 'Design Assistant'
    const assistant = await openai.beta.assistants.create({
      name: assistantName,
      model: OPENAI_MODEL,
      instructions: systemPrompt,
    })

    // 10. Create OpenAI Thread
    const thread = await openai.beta.threads.create()

    // 11. Add initial message with project context
    const initialMessageContent: any[] = [
      {
        type: 'text',
        text: projectContext,
      },
    ]

    // Add floor plan image if available (from webhook_payload)
    const floorPlanUrl = project.webhook_payload?.files?.floor_plan
    if (floorPlanUrl) {
      initialMessageContent.push({
        type: 'image_url',
        image_url: { url: floorPlanUrl },
      })
    }

    // Add visualization photos if available (up to 3 to save tokens)
    const visualizationPhotos = project.webhook_payload?.files?.visualization_photos || []
    const photosToInclude = visualizationPhotos.slice(0, 3) // Limit to 3 photos
    for (const photoUrl of photosToInclude) {
      initialMessageContent.push({
        type: 'image_url',
        image_url: { url: photoUrl },
      })
    }

    await openai.beta.threads.messages.create(thread.id, {
      role: 'user',
      content: initialMessageContent,
    })

    // 12. Run assistant to generate greeting
    const run = await openai.beta.threads.runs.createAndPoll(thread.id, {
      assistant_id: assistant.id,
    })

    if (run.status !== 'completed') {
      throw new Error(`Assistant run failed with status: ${run.status}`)
    }

    // 13. Get assistant's greeting response
    const messages = await openai.beta.threads.messages.list(thread.id, {
      order: 'desc',
      limit: 1,
    })

    const assistantMessage = messages.data[0]
    const greeting = assistantMessage?.content?.[0]?.type === 'text'
      ? assistantMessage.content[0].text.value
      : 'Hello! How can I help with your project today?'

    // 14. Save conversation to database
    const { data: conversation, error: conversationError } = await supabaseAdmin
      .from('ai_chat_conversations')
      .insert({
        project_id: project_id,
        showroom_id: showroom.id,
        thread_id: thread.id,
        assistant_id: assistant.id,
        status: 'active',
      })
      .select('id')
      .single()

    if (conversationError) {
      throw new Error(`Failed to save conversation: ${conversationError.message}`)
    }

    // 15. Save initial messages to database (context + greeting)
    await supabaseAdmin
      .from('ai_chat_messages')
      .insert([
        {
          conversation_id: conversation.id,
          role: 'assistant',
          content: greeting,
        },
      ])

    // 16. Return response
    return new Response(
      JSON.stringify({
        conversation_id: conversation.id,
        thread_id: thread.id,
        greeting: greeting,
        assistant_name: assistantName,
      } as StartChatResponse),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error starting AI chat:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

function buildProjectContext(
  project: any,
  measurements: any,
  selections: any[]
): string {
  const parts: string[] = []

  // Get customer name
  const customerName = `${project.customer_first_name || ''} ${project.customer_last_name || ''}`.trim() || 'Customer'

  // Get room info from webhook_payload if available
  const webhookPayload = project.webhook_payload || {}
  const roomInfo = webhookPayload.room || {}
  const measurementsData = webhookPayload.measurements || {}

  parts.push('=== PROJECT CONTEXT ===')
  parts.push(`Customer: ${customerName}`)
  parts.push(`Room Type: ${roomInfo.type || roomInfo.name || 'Kitchen'}`)

  // Room dimensions from webhook_payload
  if (roomInfo.ceiling_height) {
    parts.push(`Ceiling Height: ${roomInfo.ceiling_height}`)
  }

  // Measurements summary
  const summary = measurementsData.summary || {}
  if (summary.total_linear_ft) {
    parts.push(`Total Linear Feet: ${summary.total_linear_ft}'`)
  }
  if (summary.wall_count) {
    parts.push(`Walls: ${summary.wall_count}`)
  }
  if (summary.window_count) {
    parts.push(`Windows: ${summary.window_count}`)
  }
  if (summary.door_count) {
    parts.push(`Doors: ${summary.door_count}`)
  }

  // Product selections from webhook_payload
  const selectionsData = webhookPayload.selections || {}
  const selectedProducts = Object.entries(selectionsData)
    .filter(([_, value]) => value !== null)
    .map(([key, value]: [string, any]) => `- ${value.product} (${value.category_name})`)

  if (selectedProducts.length > 0) {
    parts.push('\nSelected Products:')
    parts.push(...selectedProducts)
  }

  // Mention attached images
  const hasFloorPlan = webhookPayload.files?.floor_plan
  const hasPhotos = webhookPayload.files?.visualization_photos?.length > 0

  if (hasFloorPlan || hasPhotos) {
    parts.push('\nAttached images:')
    if (hasFloorPlan) {
      parts.push('- 2D floor plan of the room')
    }
    if (hasPhotos) {
      parts.push('- Photos of the actual space')
    }
  }

  parts.push('\n=== END PROJECT CONTEXT ===')
  parts.push('\nPlease greet the customer warmly and ask about their design vision or preferences.')

  return parts.join('\n')
}

function getDefaultSystemPrompt(): string {
  return `You are a friendly interior design assistant.

Your personality:
- Warm and enthusiastic about design
- Ask one question at a time
- Use the customer's name naturally in conversation
- Show genuine interest in their vision
- Keep responses concise (2-3 sentences max)
- Use conversational language, not formal

Your goal: Learn about their style preferences, timeline, budget comfort, and any special requirements. Make them feel heard and excited about their project.

Important guidelines:
- Never discuss pricing or give quotes
- Focus on design preferences and project details
- If asked about costs, explain that the showroom team will provide a detailed quote
- Be helpful but redirect business questions to the showroom staff`
}
