'use client'

import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { LockedFeature } from '@/components/subscription/LockedFeature'
import { hasFeature, SubscriptionPlan } from '@/lib/subscription'
import {
  User,
  Mail,
  Phone,
  Download,
  Video,
  FileCode,
  FileBox,
  Image,
  Send,
  ChevronDown,
  Sparkles,
  Archive,
  RotateCcw,
  Clock,
  AlertTriangle,
  Info,
  Trash2,
  Loader2
} from 'lucide-react'
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from '@/components/ui/hover-card'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

interface Project {
  id: string
  project_name: string
  reference_number: string
  status: string
  customer_first_name: string
  customer_last_name: string
  customer_email: string
  customer_phone?: string
  submitted_at?: string
  reviewed_at?: string
  completed_at?: string
  device_model?: string
  ios_version?: string
  app_version?: string
  storage_tier?: 'hot' | 'archived' | 'restoring'
  archived_at?: string
  restore_requested_at?: string
  restore_available_until?: string
}

interface Measurement {
  id: string
  glb_file_url?: string
  usdz_file_url?: string
  video_url?: string
  preview_image_url?: string
  visualization_photo_urls?: string[]
  measurements?: any
}

interface ProjectSidebarProps {
  project: Project
  measurement?: Measurement | null
  canExportDxf?: boolean
  currentPlan?: SubscriptionPlan | null
  onStatusChange?: (status: string) => void
  onCreateQuote?: () => void
  onVisualizeKitchen?: () => void
  isCreatingQuote?: boolean
  quoteError?: string | null
  onDismissQuoteError?: () => void
  onRequestRestore?: () => void
  isRequestingRestore?: boolean
  onDeleteProject?: () => void
  isDeleting?: boolean
  className?: string
}

const statusOptions = [
  { value: 'submitted', label: 'Submitted', color: 'bg-blue-100 text-blue-800' },
  { value: 'in_review', label: 'In Review', color: 'bg-yellow-100 text-yellow-800' },
  { value: 'quoted', label: 'Quoted', color: 'bg-purple-100 text-purple-800' },
  { value: 'accepted', label: 'Accepted', color: 'bg-green-100 text-green-800' },
  { value: 'rejected', label: 'Rejected', color: 'bg-red-100 text-red-800' },
  { value: 'completed', label: 'Completed', color: 'bg-green-100 text-green-800' },
]

export function ProjectSidebar({
  project,
  measurement,
  canExportDxf = true,
  currentPlan = null,
  onStatusChange,
  onCreateQuote,
  onVisualizeKitchen,
  isCreatingQuote = false,
  quoteError = null,
  onDismissQuoteError,
  onRequestRestore,
  isRequestingRestore = false,
  onDeleteProject,
  isDeleting = false,
  className = ''
}: ProjectSidebarProps) {
  const [downloadingPhoto, setDownloadingPhoto] = useState<number | null>(null)
  const [downloadingVideo, setDownloadingVideo] = useState(false)
  const [downloadingUsdz, setDownloadingUsdz] = useState(false)
  const currentStatus = statusOptions.find(s => s.value === project.status) || statusOptions[0]

  // Download file from URL (handles cross-origin)
  const downloadFile = async (url: string, filename: string, index?: number) => {
    if (index !== undefined) setDownloadingPhoto(index)
    try {
      const response = await fetch(url)
      const blob = await response.blob()
      const blobUrl = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = blobUrl
      link.download = filename
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      URL.revokeObjectURL(blobUrl)
    } catch (error) {
      console.error('Download failed:', error)
      // Fallback: open in new tab
      window.open(url, '_blank')
    } finally {
      if (index !== undefined) setDownloadingPhoto(null)
    }
  }

  // Check feature access
  const hasAutocadExport = hasFeature(currentPlan, 'autocadExport')
  const hasAiAgent = hasFeature(currentPlan, 'aiAgent')

  const hasUsdzFile = measurement?.usdz_file_url
  const hasVideoFile = measurement?.video_url
  const visualizationPhotos = measurement?.visualization_photo_urls || []
  const hasVisualizationPhotos = visualizationPhotos.length > 0
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room
  const hasDownloadableFiles = hasUsdzFile || hasVideoFile || hasVisualizationPhotos || hasFloorPlanData

  // Storage tier states
  const isArchived = project.storage_tier === 'archived'
  const isRestoring = project.storage_tier === 'restoring'
  const hasTemporaryAccess = project.storage_tier === 'hot' && project.restore_available_until

  // Format dates for display
  const formatDate = (dateString?: string) => {
    if (!dateString) return ''
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    })
  }

  return (
    <div className={`space-y-3 ${className}`}>
      {/* Customer Information */}
      <Card className="py-0 gap-0">
        <CardHeader className="px-3 pt-3 pb-1">
          <CardTitle className="text-xs font-medium text-gray-500 uppercase tracking-wider">
            Customer
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 px-3 pb-3">
          <div className="flex items-center gap-3">
            <div className="flex-shrink-0 w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center">
              <User className="h-5 w-5 text-blue-600" />
            </div>
            <div>
              <p className="font-medium">
                {project.customer_first_name} {project.customer_last_name}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3 text-sm">
            <Mail className="h-4 w-4 text-gray-400" />
            <a
              href={`mailto:${project.customer_email}`}
              className="text-blue-600 hover:underline truncate"
            >
              {project.customer_email}
            </a>
          </div>
          {project.customer_phone && (
            <div className="flex items-center gap-3 text-sm">
              <Phone className="h-4 w-4 text-gray-400" />
              <a
                href={`tel:${project.customer_phone}`}
                className="text-blue-600 hover:underline"
              >
                {project.customer_phone}
              </a>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Status */}
      <Card className="py-0 gap-0">
        <CardHeader className="px-3 pt-3 pb-1">
          <CardTitle className="text-xs font-medium text-gray-500 uppercase tracking-wider">
            Status
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-3">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" className="w-full justify-between">
                <Badge className={currentStatus.color}>
                  {currentStatus.label}
                </Badge>
                <ChevronDown className="h-4 w-4 text-gray-400" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="w-[200px]">
              {statusOptions.map((status) => (
                <DropdownMenuItem
                  key={status.value}
                  onClick={() => onStatusChange?.(status.value)}
                  className="cursor-pointer"
                >
                  <Badge className={`${status.color} mr-2`}>
                    {status.label}
                  </Badge>
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </CardContent>
      </Card>

      {/* Downloads */}
      {hasDownloadableFiles && (
        <Card className="py-0 gap-0">
          <CardHeader className="px-3 pt-3 pb-1">
            <div className="flex items-center gap-1.5">
              <CardTitle className="text-xs font-medium text-gray-500 uppercase tracking-wider">
                Downloads
              </CardTitle>
              <HoverCard openDelay={0} closeDelay={200}>
                <HoverCardTrigger asChild>
                  <button type="button" className="inline-flex">
                    <Info className="h-3.5 w-3.5 text-gray-400 hover:text-gray-600 cursor-help" />
                  </button>
                </HoverCardTrigger>
                <HoverCardContent side="top" className="w-64 text-xs p-3">
                  <p className="font-semibold mb-1.5">Storage Policy</p>
                  <p className="text-gray-600">Files (videos, photos, 3D scans) are automatically archived after 60 days to optimize storage.</p>
                  <p className="mt-2 text-gray-500">Archived files can be restored on request. Restoration typically takes 3-5 hours.</p>
                </HoverCardContent>
              </HoverCard>
            </div>
          </CardHeader>
          <CardContent className="space-y-2 px-3 pb-3">
            {/* Archived Files Warning */}
            {isArchived && (
              <div className="p-3 rounded-lg bg-amber-50 border border-amber-200">
                <div className="flex items-start gap-3">
                  <Archive className="h-5 w-5 text-amber-600 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-amber-800">Files Archived</p>
                    <p className="text-xs text-amber-700 mt-1">
                      This project&apos;s files (video, photos, 3D scan) were automatically archived on{' '}
                      <span className="font-medium">{formatDate(project.archived_at)}</span> to optimize storage costs.
                    </p>
                    <p className="text-xs text-amber-600 mt-2">
                      Click restore to make files available for download. This typically takes 3-5 hours.
                    </p>
                    <Button
                      size="sm"
                      className="mt-3 bg-amber-600 hover:bg-amber-700"
                      onClick={onRequestRestore}
                      disabled={isRequestingRestore}
                    >
                      {isRequestingRestore ? (
                        <>
                          <div className="h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent mr-2" />
                          Requesting...
                        </>
                      ) : (
                        <>
                          <RotateCcw className="h-3 w-3 mr-2" />
                          Request Restore
                        </>
                      )}
                    </Button>
                  </div>
                </div>
              </div>
            )}

            {/* Restore In Progress */}
            {isRestoring && (
              <div className="p-3 rounded-lg bg-blue-50 border border-blue-200">
                <div className="flex items-start gap-3">
                  <Clock className="h-5 w-5 text-blue-600 flex-shrink-0 mt-0.5 animate-pulse" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-blue-800">Restore In Progress</p>
                    <p className="text-xs text-blue-700 mt-1">
                      Restore requested on {formatDate(project.restore_requested_at)}
                    </p>
                    <p className="text-xs text-blue-600 mt-2">
                      Files are being restored from archive. Your notification emails will be notified when ready (typically 3-5 hours).
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* Temporary Access Warning */}
            {hasTemporaryAccess && (
              <div className="p-3 rounded-lg bg-green-50 border border-green-200">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="h-5 w-5 text-green-600 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-green-800">Files Available</p>
                    <p className="text-xs text-green-700 mt-1">
                      Restored files are temporarily available until{' '}
                      <span className="font-medium">{formatDate(project.restore_available_until)}</span>.
                    </p>
                    <p className="text-xs text-green-600 mt-1">
                      Download them before they return to archive.
                    </p>
                  </div>
                </div>
              </div>
            )}

            {hasFloorPlanData && (
              isArchived || isRestoring ? (
                <div className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 bg-gray-50 opacity-60 cursor-not-allowed">
                  <div className="flex-shrink-0 w-8 h-8 rounded bg-gray-200 flex items-center justify-center">
                    <FileCode className="h-4 w-4 text-gray-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-500">DXF Floor Plan</p>
                    <p className="text-xs text-gray-400">AutoCAD format</p>
                  </div>
                  <Archive className="h-4 w-4 text-gray-400" />
                </div>
              ) : (
                <LockedFeature feature="autocadExport" isLocked={!hasAutocadExport}>
                  <a
                    href={hasAutocadExport ? `/api/download-dxf/${project.id}` : '#'}
                    download={hasAutocadExport ? `${project.reference_number || project.id}.dxf` : undefined}
                    className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors group"
                  >
                    <div className="flex-shrink-0 w-8 h-8 rounded bg-blue-100 flex items-center justify-center group-hover:bg-blue-200 transition-colors">
                      <FileCode className="h-4 w-4 text-blue-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium">DXF Floor Plan</p>
                      <p className="text-xs text-gray-500">AutoCAD format</p>
                    </div>
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-blue-600" />
                  </a>
                </LockedFeature>
              )
            )}
            {hasVideoFile && (
              isArchived || isRestoring ? (
                <div className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 bg-gray-50 opacity-60 cursor-not-allowed">
                  <div className="flex-shrink-0 w-8 h-8 rounded bg-gray-200 flex items-center justify-center">
                    <Video className="h-4 w-4 text-gray-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-500">Scan Video</p>
                    <p className="text-xs text-gray-400">MP4 recording</p>
                  </div>
                  <Archive className="h-4 w-4 text-gray-400" />
                </div>
              ) : (
                <button
                  onClick={async () => {
                    if (measurement?.video_url) {
                      setDownloadingVideo(true)
                      await downloadFile(measurement.video_url, `${project.reference_number}-video.mp4`)
                      setDownloadingVideo(false)
                    }
                  }}
                  disabled={downloadingVideo}
                  className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 hover:border-red-300 hover:bg-red-50 transition-colors group w-full text-left"
                >
                  <div className="flex-shrink-0 w-8 h-8 rounded bg-red-100 flex items-center justify-center group-hover:bg-red-200 transition-colors">
                    <Video className="h-4 w-4 text-red-600" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium">Scan Video</p>
                    <p className="text-xs text-gray-500">MP4 recording</p>
                  </div>
                  {downloadingVideo ? (
                    <Loader2 className="h-4 w-4 text-red-600 animate-spin" />
                  ) : (
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-red-600" />
                  )}
                </button>
              )
            )}
            {hasUsdzFile && (
              isArchived || isRestoring ? (
                <div className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 bg-gray-50 opacity-60 cursor-not-allowed">
                  <div className="flex-shrink-0 w-8 h-8 rounded bg-gray-200 flex items-center justify-center">
                    <FileBox className="h-4 w-4 text-gray-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-500">3D Model (USDZ)</p>
                    <p className="text-xs text-gray-400">AR Quick Look</p>
                  </div>
                  <Archive className="h-4 w-4 text-gray-400" />
                </div>
              ) : (
                <button
                  onClick={async () => {
                    if (measurement?.usdz_file_url) {
                      setDownloadingUsdz(true)
                      await downloadFile(measurement.usdz_file_url, `${project.reference_number}-3d-model.usdz`)
                      setDownloadingUsdz(false)
                    }
                  }}
                  disabled={downloadingUsdz}
                  className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 hover:border-purple-300 hover:bg-purple-50 transition-colors group w-full text-left"
                >
                  <div className="flex-shrink-0 w-8 h-8 rounded bg-purple-100 flex items-center justify-center group-hover:bg-purple-200 transition-colors">
                    <FileBox className="h-4 w-4 text-purple-600" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium">3D Model (USDZ)</p>
                    <p className="text-xs text-gray-500">AR Quick Look</p>
                  </div>
                  {downloadingUsdz ? (
                    <Loader2 className="h-4 w-4 text-purple-600 animate-spin" />
                  ) : (
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-purple-600" />
                  )}
                </button>
              )
            )}
            {hasVisualizationPhotos && (
              isArchived || isRestoring ? (
                <div className="p-2.5 rounded-lg border border-gray-200 bg-gray-50 opacity-60">
                  <div className="flex items-center gap-3">
                    <div className="flex-shrink-0 w-8 h-8 rounded bg-gray-200 flex items-center justify-center">
                      <Image className="h-4 w-4 text-gray-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-gray-500">Photos ({visualizationPhotos.length})</p>
                      <p className="text-xs text-gray-400">Archived</p>
                    </div>
                    <Archive className="h-4 w-4 text-gray-400" />
                  </div>
                </div>
              ) : (
                <div className="p-2.5 rounded-lg border border-gray-200">
                  <div className="flex items-center gap-3 mb-2">
                    <div className="flex-shrink-0 w-8 h-8 rounded bg-green-100 flex items-center justify-center">
                      <Image className="h-4 w-4 text-green-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium">Photos ({visualizationPhotos.length})</p>
                    </div>
                  </div>
                  <div className="grid grid-cols-3 gap-1.5 mt-2">
                    {visualizationPhotos.slice(0, 6).map((photoUrl: string, index: number) => (
                      <div key={index} className="relative group aspect-square rounded overflow-hidden">
                        <a
                          href={photoUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="block w-full h-full"
                        >
                          <img
                            src={photoUrl}
                            alt={`Photo ${index + 1}`}
                            className="w-full h-full object-cover group-hover:opacity-80 transition-opacity"
                          />
                        </a>
                        <button
                          onClick={(e) => {
                            e.preventDefault()
                            e.stopPropagation()
                            downloadFile(photoUrl, `photo-${index + 1}.jpg`, index)
                          }}
                          disabled={downloadingPhoto === index}
                          className="absolute bottom-1 right-1 p-1 bg-black/60 rounded opacity-0 group-hover:opacity-100 transition-opacity hover:bg-black/80 disabled:opacity-100"
                          title="Download photo"
                        >
                          {downloadingPhoto === index ? (
                            <Loader2 className="h-3 w-3 text-white animate-spin" />
                          ) : (
                            <Download className="h-3 w-3 text-white" />
                          )}
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )
            )}
          </CardContent>
        </Card>
      )}

      {/* Quick Actions */}
      <Card className="py-0 gap-0">
        <CardHeader className="px-3 pt-3 pb-1">
          <CardTitle className="text-xs font-medium text-gray-500 uppercase tracking-wider">
            Quick Actions
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 px-3 pb-3">
          <LockedFeature feature="aiAgent" isLocked={!hasAiAgent}>
            <Button
              className="w-full justify-start gap-2"
              variant="outline"
              onClick={hasAiAgent ? onCreateQuote : undefined}
              disabled={!hasAiAgent || isCreatingQuote}
            >
              {isCreatingQuote ? (
                <>
                  <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                  Generating Quote...
                </>
              ) : (
                <>
                  <Send className="h-4 w-4" />
                  Create Quote
                </>
              )}
            </Button>
          </LockedFeature>
          {quoteError && (
            <div className="p-3 rounded-lg bg-red-50 border border-red-200">
              <p className="text-sm text-red-700 mb-2">{quoteError}</p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="outline"
                  className="text-red-700 border-red-300 hover:bg-red-100"
                  onClick={onCreateQuote}
                >
                  Try Again
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  className="text-gray-500"
                  onClick={onDismissQuoteError}
                >
                  Dismiss
                </Button>
              </div>
            </div>
          )}
          <LockedFeature feature="aiAgent" isLocked={!hasAiAgent}>
            <Button
              className="w-full justify-start gap-2 bg-gradient-to-r from-purple-50 to-blue-50 hover:from-purple-100 hover:to-blue-100 border-purple-200"
              variant="outline"
              onClick={hasAiAgent ? onVisualizeKitchen : undefined}
              disabled={!hasAiAgent}
            >
              <Sparkles className="h-4 w-4 text-purple-600" />
              <span className="bg-gradient-to-r from-purple-600 to-blue-600 bg-clip-text text-transparent font-medium">
                Visualize Kitchen
              </span>
            </Button>
          </LockedFeature>

          {/* Delete Project */}
          <Button
            className="w-full justify-start gap-2 text-red-600 hover:text-red-700 hover:bg-red-50 border-red-200"
            variant="outline"
            onClick={onDeleteProject}
            disabled={isDeleting}
          >
            {isDeleting ? (
              <>
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-red-600 border-t-transparent" />
                Deleting...
              </>
            ) : (
              <>
                <Trash2 className="h-4 w-4" />
                Delete Project
              </>
            )}
          </Button>
        </CardContent>
      </Card>

      {/* Device Info (subtle) */}
      {(project.device_model || project.ios_version || project.app_version) && (
        <div className="px-1 text-xs text-gray-400">
          <div className="flex items-center gap-2 flex-wrap">
            {project.device_model && <span>{project.device_model}</span>}
            {project.ios_version && <span>iOS {project.ios_version}</span>}
            {project.app_version && <span>v{project.app_version}</span>}
          </div>
        </div>
      )}
    </div>
  )
}
