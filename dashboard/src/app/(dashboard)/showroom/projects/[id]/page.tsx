import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { InteractiveFloorPlan } from '@/components/floor-plan/InteractiveFloorPlan'
import { DxfPreview } from '@/components/dxf-preview/DxfPreview'
import { ProjectSidebarWrapper } from '@/components/project/ProjectSidebarWrapper'
import { RoomMeasurementsSection } from '@/components/project/RoomMeasurementsSection'
import { ProductSelectionsSection } from '@/components/project/ProductSelectionsSection'
import { LockedDxfTab } from '@/components/project/LockedDxfTab'
import { hasFeature, SubscriptionPlan } from '@/lib/subscription'
import {
  ArrowLeft,
  Layers,
  FileCode,
  FileText,
  Lock,
  PenTool,
  Image as ImageIcon,
  Video,
  Phone,
} from 'lucide-react'
import { WebhookPayloadViewer } from '@/components/webhook/WebhookPayloadViewer'
import { QuoteEmailSection } from '@/components/quote/QuoteEmailSection'
import { ChatHistorySection } from '@/components/project/ChatHistorySection'
import { DesignRequestButton } from '@/components/design/DesignRequestButton'
import { DesignStatusCard } from '@/components/design/DesignStatusCard'
import { DesignFilesSection } from '@/components/design/DesignFilesSection'
import { DesignChatWrapper } from '@/components/design/DesignChatWrapper'
import { WhiteboardGallery } from '@/components/project/WhiteboardGallery'
import { PhotoLightbox } from '@/components/project/PhotoLightbox'

interface ProjectDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function ProjectDetailPage({ params }: ProjectDetailPageProps) {
  const { id } = await params
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get user's showroom
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('showroom_id')
    .eq('user_id', user.id)
    .single()

  if (!showroomUser) redirect('/login')

  // Get showroom subscription plan, code, and visualization settings
  const { data: showroom } = await supabase
    .from('showrooms')
    .select('subscription_plan, subscription_status, showroom_code, visualize_kitchen_enabled, quote_webhook_url')
    .eq('id', showroomUser.showroom_id)
    .single()

  // Check if DXF export is available based on plan
  const hasAutocadExport = hasFeature(showroom?.subscription_plan as SubscriptionPlan | null, 'autocadExport')
  const canExportDxf = hasAutocadExport

  // Check if voice agent is globally enabled
  const { data: voiceAgentSetting } = await supabase
    .from('platform_settings')
    .select('value')
    .eq('key', 'voice_agent_globally_enabled')
    .limit(1)

  const voiceAgentEnabled = voiceAgentSetting && voiceAgentSetting.length > 0
    ? voiceAgentSetting[0].value === 'true'
    : false

  // Get project with measurements and selections
  const { data: project, error } = await supabase
    .from('projects')
    .select('*')
    .eq('id', id)
    .eq('showroom_id', showroomUser.showroom_id)
    .single()

  if (error || !project) {
    notFound()
  }

  // Get customer address from project table
  const customerAddress: string | null = project.end_client_address || null

  // Distance is stored on the project (calculated at submission time)
  const distanceMiles: number | null = project.distance_miles ?? null
  const driveTimeMinutes: number | null = project.drive_time_minutes ?? null

  // Get measurements
  const { data: measurements } = await supabase
    .from('project_measurements')
    .select('*')
    .eq('project_id', id)

  // Get selections with product and category info
  const { data: selections } = await supabase
    .from('project_selections')
    .select(`
      *,
      categories (name),
      products (name, image_url)
    `)
    .eq('project_id', id)

  // Get addon selections
  const { data: addonSelections } = await supabase
    .from('project_addon_selections')
    .select('*')
    .eq('project_id', id)
    .eq('is_selected', true)

  // Get quote email (latest one for this project)
  const { data: quoteEmails } = await supabase
    .from('quote_emails')
    .select('*')
    .eq('project_id', id)
    .order('created_at', { ascending: false })
    .limit(1)

  const quoteEmail = quoteEmails && quoteEmails.length > 0 ? quoteEmails[0] : null

  // Get AI chat conversation for this project
  const { data: chatConversation } = await supabase
    .from('ai_chat_conversations')
    .select('id, status, message_count, summary, started_at, last_message_at, completed_at')
    .eq('project_id', id)
    .single()

  // Get chat messages if conversation exists
  let chatMessages: { id: string; role: string; content: string; created_at: string }[] = []
  if (chatConversation) {
    const { data: messages } = await supabase
      .from('ai_chat_messages')
      .select('id, role, content, created_at')
      .eq('conversation_id', chatConversation.id)
      .order('created_at', { ascending: true })

    chatMessages = messages || []
  }

  // Get showroom AI settings
  const { data: showroomAiSettings } = await supabase
    .from('showrooms')
    .select('ai_assistant_name, ai_assistant_avatar_url')
    .eq('id', showroomUser.showroom_id)
    .single()

  // Check if showroom has price catalog uploaded
  const { count: priceCatalogCount } = await supabase
    .from('price_catalog')
    .select('*', { count: 'exact', head: true })
    .eq('showroom_id', showroomUser.showroom_id)

  const hasPriceCatalog = (priceCatalogCount ?? 0) > 0

  // Fetch design request for this project
  const { data: designRequest } = await supabase
    .from('design_requests')
    .select('*, designers(full_name)')
    .eq('project_id', project.id)
    .single()

  // Get showroom user info for design chat
  const { data: currentShowroomUser } = await supabase
    .from('showroom_users')
    .select('id, full_name')
    .eq('user_id', user.id)
    .eq('showroom_id', showroomUser.showroom_id)
    .single()

  // Get whiteboards
  const { data: whiteboards } = await supabase
    .from('project_whiteboards')
    .select('*')
    .eq('project_id', id)
    .order('created_at', { ascending: true })

  const { getStatusColor, getStatusLabel } = await import('@/lib/project-status')

  const updateStatus = async (formData: FormData) => {
    'use server'

    const newStatus = formData.get('status') as string
    const supabase = await createClient()

    await supabase
      .from('projects')
      .update({
        status: newStatus,
        reviewed_at: newStatus === 'in_review' ? new Date().toISOString() : undefined,
      })
      .eq('id', id)

    revalidatePath(`/showroom/projects/${id}`)
  }

  const createQuote = async () => {
    'use server'

    const cabinetAiServiceUrl = process.env.CABINET_AI_SERVICE_URL || 'https://cabinetai.nextlyn.ai'

    const supabase = await createClient()

    // Get project with webhook payload and showroom_id
    const { data: projectData, error: projectError } = await supabase
      .from('projects')
      .select('webhook_payload, reference_number, showroom_id')
      .eq('id', id)
      .single()

    if (projectError || !projectData) {
      console.error('Failed to fetch project:', projectError)
      throw new Error('Project not found')
    }

    if (!projectData.webhook_payload) {
      throw new Error('No webhook payload stored for this project')
    }

    // Get showroom details for callback URL
    const { data: showroomData } = await supabase
      .from('showrooms')
      .select('id, name, showroom_code, webhook_url, phone, email, notification_emails')
      .eq('id', projectData.showroom_id)
      .single()

    // Get the latest preview_image_url from project_measurements
    const { data: measurementsData } = await supabase
      .from('project_measurements')
      .select('preview_image_url')
      .eq('project_id', id)
      .single()

    // Build the payload with latest floor plan URL and showroom details
    const storedPayload = projectData.webhook_payload as Record<string, any>
    const webhookPayload = {
      ...storedPayload,
      event: 'quote.requested',
      showroom_id: projectData.showroom_id,
      callback_url: showroomData?.webhook_url || null,
      showroom: {
        id: showroomData?.id,
        name: showroomData?.name,
        code: showroomData?.showroom_code,
        phone: showroomData?.phone || null,
        email: showroomData?.email || null,
        notification_emails: showroomData?.notification_emails
          ? showroomData.notification_emails.split(',').map((e: string) => e.trim()).filter((e: string) => e.length > 0)
          : [],
        postbackUrl: showroomData?.webhook_url || null,
      },
      files: {
        ...(storedPayload.files || {}),
        floor_plan: measurementsData?.preview_image_url || storedPayload.files?.floor_plan || null,
      },
      generate_quote: true,
      triggered_at: new Date().toISOString(),
    }

    // Send to estimate API endpoint with timeout for Cloud Run cold starts
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 60000) // 60 second timeout

    let response: Response
    try {
      response = await fetch(
        `${cabinetAiServiceUrl}/api/estimate`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(webhookPayload),
          signal: controller.signal,
        }
      )
    } catch (fetchError) {
      clearTimeout(timeoutId)
      console.error('Fetch error connecting to Cabinet AI service:', fetchError)
      if (fetchError instanceof Error && fetchError.name === 'AbortError') {
        throw new Error('Request timed out - the quote service is taking too long to respond')
      }
      throw new Error(`Failed to connect to quote service: ${fetchError instanceof Error ? fetchError.message : 'Unknown error'}`)
    } finally {
      clearTimeout(timeoutId)
    }

    if (!response.ok) {
      let errorMessage = 'Failed to send to estimate API'
      try {
        const error = await response.json()
        console.error('Failed to send to estimate API:', error)
        errorMessage = error.error || errorMessage
      } catch {
        console.error('Failed to send to estimate API, status:', response.status)
      }
      throw new Error(errorMessage)
    }

    // Update project status to quoted
    await supabase
      .from('projects')
      .update({
        status: 'quoted',
        quoted_at: new Date().toISOString(),
      })
      .eq('id', id)

    revalidatePath(`/showroom/projects/${id}`)
  }

  const deleteProject = async () => {
    'use server'

    const supabase = await createClient()

    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('Not authenticated')

    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/delete-project`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ project_id: id }),
      }
    )

    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }))
      console.error('Error deleting project:', error)
      throw new Error(error.error || 'Failed to delete project')
    }
  }

  // Extract scan data
  const measurement = measurements && measurements.length > 0 ? measurements[0] : null
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room
  const hasScanData = hasFloorPlanData

  // Collect photos from measurements
  const photos: { url: string; label: string }[] = []
  if (measurements) {
    for (const m of measurements) {
      if (m.preview_image_url) {
        photos.push({ url: m.preview_image_url, label: 'Floor Plan Preview' })
      }
      if (m.visualization_photo_urls && Array.isArray(m.visualization_photo_urls)) {
        for (const photoUrl of m.visualization_photo_urls) {
          photos.push({ url: photoUrl, label: `Photo ${photos.length + 1}` })
        }
      }
    }
  }

  // Collect videos from measurements
  const videos: { url: string; thumbnail?: string | null; label: string }[] = []
  if (measurements) {
    for (const m of measurements) {
      if (m.video_url) {
        videos.push({
          url: m.video_url,
          thumbnail: m.video_thumbnail_url || null,
          label: m.room_name || 'Room Video',
        })
      }
    }
  }

  return (
    <div className="max-w-full space-y-6">
      {/* Header - Compact */}
      <div className="flex items-center gap-4">
        <Link href="/showroom/projects">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3">
            <h1 className="text-xl font-bold truncate">
              {project.customer_first_name} {project.customer_last_name}
            </h1>
            <Badge className={getStatusColor(project.status)}>
              {getStatusLabel(project.status)}
            </Badge>
          </div>
          <p className="text-sm text-gray-500">
            Ref: <span className="font-mono">{project.reference_number}</span>
          </p>
        </div>
      </div>

      {/* Two-Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-6 max-w-full overflow-hidden">
        {/* Left Column - Main Content */}
        <div className="space-y-4 min-w-0">
          {/* Floor Plan Viewer */}
          {hasScanData ? (
            <Card className="overflow-hidden">
              <Tabs defaultValue="2d" className="w-full">
                <div className="flex items-center justify-between px-4 py-3 border-b bg-gray-50/50">
                  <TabsList>
                    <TabsTrigger value="2d" className="gap-2">
                      <Layers className="h-4 w-4" />
                      2D Floor Plan
                    </TabsTrigger>
                    {canExportDxf ? (
                      <TabsTrigger value="dxf" className="gap-2">
                        <FileCode className="h-4 w-4" />
                        DXF Preview
                      </TabsTrigger>
                    ) : (
                      <LockedDxfTab />
                    )}
                  </TabsList>
                </div>

                <TabsContent value="2d" className="m-0">
                  <InteractiveFloorPlan
                    measurements={measurement?.measurements}
                    minimal
                    measurementId={measurement?.id}
                    previewImageUrl={measurement?.preview_image_url}
                    showroomCode={showroom?.showroom_code}
                    projectId={project.id}
                  />
                </TabsContent>

                {canExportDxf && (
                  <TabsContent value="dxf" className="m-0">
                    <DxfPreview measurements={measurement?.measurements} />
                  </TabsContent>
                )}
              </Tabs>
            </Card>
          ) : (
            // No scan data available
            <Card>
              <CardContent className="py-12">
                <div className="flex flex-col items-center justify-center text-center">
                  <div className="w-16 h-16 rounded-full bg-gray-100 flex items-center justify-center mb-4">
                    <Layers className="h-8 w-8 text-gray-400" />
                  </div>
                  <h3 className="text-lg font-medium text-gray-900 mb-2">No Scan Data Available</h3>
                  <p className="text-gray-500 max-w-md">
                    This project does not include a room scan. The customer may have submitted selections without scanning.
                  </p>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Photos Section */}
          {photos.length > 0 && (
            <Card>
              <div className="px-4 py-3 border-b bg-gray-50/50 flex items-center gap-2">
                <ImageIcon className="h-4 w-4 text-gray-500" />
                <h3 className="font-semibold text-sm">Photos</h3>
                <Badge variant="secondary" className="text-xs ml-auto">
                  {photos.length}
                </Badge>
              </div>
              <CardContent className="p-4">
                <PhotoLightbox photos={photos} />
              </CardContent>
            </Card>
          )}

          {/* Videos Section */}
          {videos.length > 0 && (
            <Card>
              <div className="px-4 py-3 border-b bg-gray-50/50 flex items-center gap-2">
                <Video className="h-4 w-4 text-gray-500" />
                <h3 className="font-semibold text-sm">Videos</h3>
              </div>
              <CardContent className="p-4 space-y-4">
                {videos.map((v, idx) => (
                  <div key={idx} className="space-y-1.5">
                    <p className="text-sm font-medium text-gray-700">{v.label}</p>
                    <video
                      controls
                      className="w-full rounded-lg bg-black max-h-[400px]"
                      poster={v.thumbnail || undefined}
                      preload="metadata"
                    >
                      <source src={v.url} />
                      Your browser does not support the video tag.
                    </video>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}

          {/* Expandable Sections */}
          <div className="space-y-3">
            {/* Room Measurements */}
            <RoomMeasurementsSection measurement={measurement} defaultOpen={true} />

            {/* Product Selections */}
            <ProductSelectionsSection selections={selections} addonSelections={addonSelections} defaultOpen={false} />

            {/* Quote Email Preview */}
            {quoteEmail && (
              <QuoteEmailSection
                quoteEmail={quoteEmail}
                currentPlan={showroom?.subscription_plan as SubscriptionPlan | null}
              />
            )}

            {/* AI Designer Agent Chat History */}
            <ChatHistorySection
              conversation={chatConversation}
              messages={chatMessages as { id: string; role: 'user' | 'assistant'; content: string; created_at: string }[]}
              assistantName={showroomAiSettings?.ai_assistant_name || 'Design Assistant'}
              assistantAvatarUrl={showroomAiSettings?.ai_assistant_avatar_url || null}
            />

            {/* Webhook Payload */}
            {project.webhook_payload && (
              <WebhookPayloadViewer payload={project.webhook_payload as Record<string, unknown>} />
            )}

            {/* Customer Notes */}
            {project.project_notes && (
              <Accordion type="single" collapsible>
                <AccordionItem value="notes" className="border rounded-lg px-4">
                  <AccordionTrigger className="hover:no-underline py-3">
                    <div className="flex items-center gap-3">
                      <div className="p-2 bg-blue-100 rounded-lg">
                        <FileText className="h-4 w-4 text-blue-600" />
                      </div>
                      <div className="text-left">
                        <h3 className="font-semibold text-gray-900">Customer Notes</h3>
                      </div>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="pt-1 pb-4">
                    <p className="text-gray-600 whitespace-pre-wrap">{project.project_notes}</p>
                  </AccordionContent>
                </AccordionItem>
              </Accordion>
            )}

            {/* Whiteboards */}
            {whiteboards && whiteboards.length > 0 && (
              <Accordion type="single" collapsible defaultValue="whiteboards">
                <AccordionItem value="whiteboards" className="border rounded-lg px-4">
                  <AccordionTrigger className="hover:no-underline py-3">
                    <div className="flex items-center gap-3">
                      <div className="p-2 bg-orange-100 rounded-lg">
                        <PenTool className="h-4 w-4 text-orange-600" />
                      </div>
                      <div className="text-left">
                        <h3 className="font-semibold text-gray-900">Whiteboards</h3>
                        <p className="text-xs text-gray-500">{whiteboards.length} item{whiteboards.length === 1 ? '' : 's'}</p>
                      </div>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="pt-1 pb-4">
                    <WhiteboardGallery whiteboards={whiteboards} />
                  </AccordionContent>
                </AccordionItem>
              </Accordion>
            )}
          </div>
        </div>

        {/* Right Column - Sidebar */}
        <div className="lg:sticky lg:top-6 lg:self-start min-w-0 space-y-4">
          <ProjectSidebarWrapper
            project={{ ...project, customer_address: customerAddress, distance_miles: distanceMiles, drive_time_minutes: driveTimeMinutes, distance_error: project.distance_error ?? null }}
            measurement={measurement}
            canExportDxf={canExportDxf}
            visualizeKitchenEnabled={showroom?.visualize_kitchen_enabled ?? false}
            hasPriceCatalog={hasPriceCatalog}
            showroomId={showroomUser.showroom_id}
            designRequest={designRequest}
            voiceAgentEnabled={voiceAgentEnabled}
            onStatusChange={async (status) => {
              'use server'
              const formData = new FormData()
              formData.set('status', status)
              await updateStatus(formData)
            }}
            onCreateQuote={createQuote}
            onDeleteProject={deleteProject}
          />

          {/* Design Status & Files */}
          {designRequest && (
            <>
              <DesignStatusCard
                designRequest={designRequest}
                designerName={(designRequest as any)?.designers?.full_name}
              />

              {/* Design Chat */}
              {currentShowroomUser && (
                <DesignChatWrapper
                  designRequestId={designRequest.id}
                  currentUserId={currentShowroomUser.id}
                  currentUserName={currentShowroomUser.full_name}
                />
              )}

              {/* Design Files */}
              {['delivered', 'approved', 'revision_requested', 'completed'].includes(designRequest.status) && (
                <DesignFilesSection designRequestId={designRequest.id} />
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
