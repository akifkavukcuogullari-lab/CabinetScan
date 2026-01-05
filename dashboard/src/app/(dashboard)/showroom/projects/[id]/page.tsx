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
  Lock
} from 'lucide-react'
import { WebhookPayloadViewer } from '@/components/webhook/WebhookPayloadViewer'
import { QuoteEmailSection } from '@/components/quote/QuoteEmailSection'

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

  // Get showroom subscription plan
  const { data: showroom } = await supabase
    .from('showrooms')
    .select('subscription_plan, subscription_status')
    .eq('id', showroomUser.showroom_id)
    .single()

  // Check if DXF export is available based on plan
  const hasAutocadExport = hasFeature(showroom?.subscription_plan as SubscriptionPlan | null, 'autocadExport')
  const canExportDxf = hasAutocadExport

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

  const statusColors: Record<string, string> = {
    draft: 'bg-gray-100 text-gray-800',
    submitted: 'bg-blue-100 text-blue-800',
    in_review: 'bg-yellow-100 text-yellow-800',
    quoted: 'bg-purple-100 text-purple-800',
    accepted: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800',
    completed: 'bg-green-100 text-green-800',
  }

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

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

    if (!supabaseUrl || !supabaseKey) {
      console.error('Missing Supabase environment variables')
      throw new Error('Server configuration error: Missing Supabase credentials')
    }

    // Trigger the webhook for this project
    const response = await fetch(
      `${supabaseUrl}/functions/v1/trigger-webhook`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${supabaseKey}`
        },
        body: JSON.stringify({ project_id: id })
      }
    )

    if (!response.ok) {
      let errorMessage = 'Failed to trigger webhook'
      try {
        const error = await response.json()
        console.error('Failed to trigger webhook:', error)
        errorMessage = error.error || errorMessage
      } catch {
        console.error('Failed to trigger webhook, status:', response.status)
      }
      throw new Error(errorMessage)
    }

    // Update project status to quoted
    const supabase = await createClient()
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

    // Get project with file URLs to delete from storage
    const { data: projectData } = await supabase
      .from('projects')
      .select('scan_file_url, preview_image_url, video_url')
      .eq('id', id)
      .single()

    // Get measurements with file URLs
    const { data: measurementsData } = await supabase
      .from('project_measurements')
      .select('usdz_file_url, video_url, preview_image_url, visualization_photo_urls')
      .eq('project_id', id)

    // Collect all storage paths to delete
    const storagePaths: string[] = []

    // Helper to extract path from URL
    const extractPath = (url: string | null | undefined, bucket: string) => {
      if (!url) return null
      const match = url.match(new RegExp(`/storage/v1/object/public/${bucket}/(.+)`))
      return match ? match[1] : null
    }

    // Project files
    if (projectData?.scan_file_url) {
      const path = extractPath(projectData.scan_file_url, 'scans')
      if (path) storagePaths.push(`scans/${path}`)
    }
    if (projectData?.preview_image_url) {
      const path = extractPath(projectData.preview_image_url, 'scans')
      if (path) storagePaths.push(`scans/${path}`)
    }
    if (projectData?.video_url) {
      const path = extractPath(projectData.video_url, 'scans')
      if (path) storagePaths.push(`scans/${path}`)
    }

    // Measurement files
    if (measurementsData) {
      for (const m of measurementsData) {
        if (m.usdz_file_url) {
          const path = extractPath(m.usdz_file_url, 'scans')
          if (path) storagePaths.push(`scans/${path}`)
        }
        if (m.video_url) {
          const path = extractPath(m.video_url, 'scans')
          if (path) storagePaths.push(`scans/${path}`)
        }
        if (m.preview_image_url) {
          const path = extractPath(m.preview_image_url, 'scans')
          if (path) storagePaths.push(`scans/${path}`)
        }
        if (m.visualization_photo_urls && Array.isArray(m.visualization_photo_urls)) {
          for (const photoUrl of m.visualization_photo_urls) {
            const path = extractPath(photoUrl, 'scans')
            if (path) storagePaths.push(`scans/${path}`)
          }
        }
      }
    }

    // Delete files from storage (scans bucket)
    if (storagePaths.length > 0) {
      const pathsOnly = storagePaths.map(p => p.replace('scans/', ''))
      await supabase.storage.from('scans').remove(pathsOnly)
    }

    // Delete related database records (cascade should handle most, but be explicit)
    await supabase.from('quote_emails').delete().eq('project_id', id)
    await supabase.from('project_addon_selections').delete().eq('project_id', id)
    await supabase.from('project_selections').delete().eq('project_id', id)
    await supabase.from('project_measurements').delete().eq('project_id', id)

    // Finally delete the project
    const { error } = await supabase.from('projects').delete().eq('id', id)

    if (error) {
      console.error('Error deleting project:', error)
      throw new Error('Failed to delete project')
    }

    // Redirect will happen on client side
  }

  // Extract scan data
  const measurement = measurements && measurements.length > 0 ? measurements[0] : null
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room
  const hasScanData = hasFloorPlanData

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
            <Badge className={statusColors[project.status]}>
              {project.status.replace('_', ' ')}
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
                  <InteractiveFloorPlan measurements={measurement?.measurements} minimal />
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
          </div>
        </div>

        {/* Right Column - Sidebar */}
        <div className="lg:sticky lg:top-6 lg:self-start min-w-0">
          <ProjectSidebarWrapper
            project={project}
            measurement={measurement}
            canExportDxf={canExportDxf}
            onStatusChange={async (status) => {
              'use server'
              const formData = new FormData()
              formData.set('status', status)
              await updateStatus(formData)
            }}
            onCreateQuote={createQuote}
            onDeleteProject={deleteProject}
          />
        </div>
      </div>
    </div>
  )
}
