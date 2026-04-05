import { createClient } from '@/lib/supabase/server'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { InteractiveFloorPlan } from '@/components/floor-plan/InteractiveFloorPlan'
import { DesignChatWrapper } from '@/components/design/DesignChatWrapper'
import { DesignerStatusControls } from '@/components/design/DesignerStatusControls'
import { DesignFileUpload } from '@/components/design/DesignFileUpload'
import {
  ArrowLeft,
  Layers,
  Ruler,
  DoorOpen,
  Square,
  Wind,
  FileText,
  Image as ImageIcon,
  Video,
  PenTool,
} from 'lucide-react'
import { PhotoLightbox } from '@/components/project/PhotoLightbox'
import { WhiteboardGallery } from '@/components/project/WhiteboardGallery'

interface DesignerProjectDetailPageProps {
  params: Promise<{ id: string }>
}

const designStatusConfig: Record<string, { label: string; color: string }> = {
  pending: { label: 'Pending', color: 'bg-orange-100 text-orange-800' },
  accepted: { label: 'Accepted', color: 'bg-blue-100 text-blue-800' },
  in_progress: { label: 'In Progress', color: 'bg-indigo-100 text-indigo-800' },
  delivered: { label: 'Delivered', color: 'bg-purple-100 text-purple-800' },
  approved: { label: 'Approved', color: 'bg-green-100 text-green-800' },
  revision_requested: { label: 'Revision Requested', color: 'bg-yellow-100 text-yellow-800' },
  completed: { label: 'Completed', color: 'bg-green-100 text-green-800' },
  canceled: { label: 'Canceled', color: 'bg-gray-100 text-gray-800' },
}

const priorityConfig: Record<string, { label: string; color: string }> = {
  low: { label: 'Low', color: 'bg-gray-100 text-gray-700' },
  normal: { label: 'Normal', color: 'bg-blue-50 text-blue-700' },
  high: { label: 'High', color: 'bg-orange-100 text-orange-700' },
  urgent: { label: 'Urgent', color: 'bg-red-100 text-red-700' },
}

export default async function DesignerProjectDetailPage({ params }: DesignerProjectDetailPageProps) {
  const { id: designRequestId } = await params
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get designer info
  const { data: designer } = await supabase
    .from('designers')
    .select('id, full_name')
    .eq('user_id', user.id)
    .single()

  if (!designer) redirect('/login')

  // Fetch design request
  const { data: designRequest, error: drError } = await supabase
    .from('design_requests')
    .select('*')
    .eq('id', designRequestId)
    .single()

  if (drError || !designRequest) {
    notFound()
  }

  // Fetch project data via designer_project_view (strips sensitive data)
  const { data: project, error: projectError } = await supabase
    .from('designer_project_view')
    .select('*')
    .eq('design_request_id', designRequestId)
    .single()

  if (projectError || !project) {
    notFound()
  }

  // Fetch measurements
  const { data: measurements } = await supabase
    .from('project_measurements')
    .select('*')
    .eq('project_id', project.id)

  // Fetch design files to determine if any have been uploaded
  const { data: designFiles } = await supabase
    .from('design_files')
    .select('id')
    .eq('design_request_id', designRequestId)
    .limit(1)

  const hasUploadedFiles = (designFiles?.length ?? 0) > 0

  // Fetch whiteboards
  const { data: whiteboards } = await supabase
    .from('project_whiteboards')
    .select('*')
    .eq('project_id', project.id)
    .order('created_at', { ascending: true })

  // Extract measurement data
  const measurement = measurements && measurements.length > 0 ? measurements[0] : null
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room

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

  const designStatus = designStatusConfig[designRequest.status] || designStatusConfig.pending
  const priority = priorityConfig[designRequest.priority || 'normal'] || priorityConfig.normal
  const showChat = designRequest.status !== 'pending' && designRequest.status !== 'canceled'

  return (
    <div className="max-w-full space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Link href="/designer/projects">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-xl font-bold truncate">
              Project {project.reference_number}
            </h1>
            <Badge className={designStatus.color}>{designStatus.label}</Badge>
            <Badge variant="outline" className={priority.color}>{priority.label}</Badge>
          </div>
        </div>
      </div>

      {/* Two-Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-6 max-w-full overflow-hidden">
        {/* Left Column - Main Content */}
        <div className="space-y-5 min-w-0">
          {/* Floor Plan */}
          {hasFloorPlanData ? (
            <Card className="overflow-hidden">
              <div className="px-4 py-3 border-b bg-gray-50/50 flex items-center gap-2">
                <Layers className="h-4 w-4 text-gray-500" />
                <h3 className="font-semibold text-sm">Floor Plan</h3>
              </div>
              <InteractiveFloorPlan
                measurements={measurement?.measurements}
                minimal
                measurementId={measurement?.id}
                previewImageUrl={measurement?.preview_image_url}
                projectId={project.id}
              />
            </Card>
          ) : (
            <Card>
              <CardContent className="py-10">
                <div className="flex flex-col items-center justify-center text-center">
                  <div className="w-14 h-14 rounded-full bg-gray-100 flex items-center justify-center mb-3">
                    <Layers className="h-7 w-7 text-gray-400" />
                  </div>
                  <h3 className="text-base font-medium text-gray-900 mb-1">No Floor Plan Available</h3>
                  <p className="text-sm text-gray-500 max-w-sm">
                    This project does not include a room scan.
                  </p>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Room Measurements */}
          {measurement && (
            <Card>
              <div className="px-4 py-3 border-b bg-gray-50/50 flex items-center gap-2">
                <Ruler className="h-4 w-4 text-gray-500" />
                <h3 className="font-semibold text-sm">Room Measurements</h3>
              </div>
              <CardContent className="p-4">
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4">
                  <MeasurementStat
                    icon={<Square className="h-4 w-4 text-blue-500" />}
                    label="Walls"
                    value={measurement.wall_count ?? '-'}
                  />
                  <MeasurementStat
                    icon={<Wind className="h-4 w-4 text-cyan-500" />}
                    label="Windows"
                    value={measurement.window_count ?? '-'}
                  />
                  <MeasurementStat
                    icon={<DoorOpen className="h-4 w-4 text-amber-500" />}
                    label="Doors"
                    value={measurement.door_count ?? '-'}
                  />
                  <MeasurementStat
                    icon={<Ruler className="h-4 w-4 text-green-500" />}
                    label="Linear Ft"
                    value={measurement.total_linear_ft != null ? `${Number(measurement.total_linear_ft).toFixed(1)}` : '-'}
                  />
                  <MeasurementStat
                    icon={<Layers className="h-4 w-4 text-purple-500" />}
                    label="Sq Ft"
                    value={measurement.total_sq_ft != null ? `${Number(measurement.total_sq_ft).toFixed(1)}` : '-'}
                  />
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

          {/* Whiteboards Section */}
          {whiteboards && whiteboards.length > 0 && (
            <Card>
              <div className="px-4 py-3 border-b bg-gray-50/50 flex items-center gap-2">
                <PenTool className="h-4 w-4 text-gray-500" />
                <h3 className="font-semibold text-sm">Whiteboards</h3>
                <Badge variant="secondary" className="text-xs ml-auto">
                  {whiteboards.length}
                </Badge>
              </div>
              <CardContent className="p-4">
                <WhiteboardGallery whiteboards={whiteboards} />
              </CardContent>
            </Card>
          )}

          {/* Design Notes / Brief */}
          {designRequest.notes && (
            <Card>
              <div className="px-4 py-3 border-b bg-gray-50/50 flex items-center gap-2">
                <FileText className="h-4 w-4 text-gray-500" />
                <h3 className="font-semibold text-sm">Design Brief</h3>
              </div>
              <CardContent className="p-4">
                <p className="text-sm text-gray-700 whitespace-pre-wrap leading-relaxed">
                  {designRequest.notes}
                </p>
              </CardContent>
            </Card>
          )}

          {/* Project Notes removed - may contain customer personal info */}
        </div>

        {/* Right Column - Sidebar */}
        <div className="lg:sticky lg:top-6 lg:self-start min-w-0 space-y-4">
          {/* Status Controls */}
          <DesignerStatusControls
            designRequestId={designRequestId}
            currentStatus={designRequest.status}
            hasUploadedFiles={hasUploadedFiles}
            estimatedCompletionAt={designRequest.estimated_completion_at}
            designerId={designer.id}
            rejectionReason={designRequest.rejection_reason}
          />

          {/* Design File Upload */}
          <DesignFileUpload
            designRequestId={designRequestId}
            designerId={designer.id}
            currentStatus={designRequest.status}
          />

          {/* Chat */}
          {showChat && (
            <DesignChatWrapper
              designRequestId={designRequestId}
              currentUserId={designer.id}
              currentUserName={designer.full_name}
              currentUserType="designer"
            />
          )}
        </div>
      </div>
    </div>
  )
}

function MeasurementStat({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: string | number
}) {
  return (
    <div className="flex flex-col items-center gap-1.5 p-3 rounded-lg bg-gray-50">
      {icon}
      <span className="text-lg font-semibold text-gray-900">{value}</span>
      <span className="text-xs text-gray-500">{label}</span>
    </div>
  )
}
