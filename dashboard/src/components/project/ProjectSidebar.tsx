'use client'

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
  Sparkles
} from 'lucide-react'
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
  className = ''
}: ProjectSidebarProps) {
  const currentStatus = statusOptions.find(s => s.value === project.status) || statusOptions[0]

  // Check feature access
  const hasAutocadExport = hasFeature(currentPlan, 'autocadExport')
  const hasAiAgent = hasFeature(currentPlan, 'aiAgent')

  const hasUsdzFile = measurement?.usdz_file_url
  const hasVideoFile = measurement?.video_url
  const visualizationPhotos = measurement?.visualization_photo_urls || []
  const hasVisualizationPhotos = visualizationPhotos.length > 0
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room
  const hasDownloadableFiles = hasUsdzFile || hasVideoFile || hasVisualizationPhotos || hasFloorPlanData

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
            <CardTitle className="text-xs font-medium text-gray-500 uppercase tracking-wider">
              Downloads
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 px-3 pb-3">
            {hasFloorPlanData && (
              <LockedFeature feature="autocadExport" isLocked={!hasAutocadExport}>
                <a
                  href={hasAutocadExport ? `/api/export/dxf?project_id=${project.id}` : '#'}
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
            )}
            {hasVideoFile && (
              <a
                href={measurement?.video_url}
                download
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 hover:border-red-300 hover:bg-red-50 transition-colors group"
              >
                <div className="flex-shrink-0 w-8 h-8 rounded bg-red-100 flex items-center justify-center group-hover:bg-red-200 transition-colors">
                  <Video className="h-4 w-4 text-red-600" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">Scan Video</p>
                  <p className="text-xs text-gray-500">MP4 recording</p>
                </div>
                <Download className="h-4 w-4 text-gray-400 group-hover:text-red-600" />
              </a>
            )}
            {hasUsdzFile && (
              <a
                href={measurement?.usdz_file_url}
                download
                className="flex items-center gap-3 p-2.5 rounded-lg border border-gray-200 hover:border-purple-300 hover:bg-purple-50 transition-colors group"
              >
                <div className="flex-shrink-0 w-8 h-8 rounded bg-purple-100 flex items-center justify-center group-hover:bg-purple-200 transition-colors">
                  <FileBox className="h-4 w-4 text-purple-600" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">3D Model (USDZ)</p>
                  <p className="text-xs text-gray-500">AR Quick Look</p>
                </div>
                <Download className="h-4 w-4 text-gray-400 group-hover:text-purple-600" />
              </a>
            )}
            {hasVisualizationPhotos && (
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
                    <a
                      key={index}
                      href={photoUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="aspect-square rounded overflow-hidden hover:opacity-80 transition-opacity"
                    >
                      <img
                        src={photoUrl}
                        alt={`Photo ${index + 1}`}
                        className="w-full h-full object-cover"
                      />
                    </a>
                  ))}
                </div>
              </div>
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
              disabled={!hasAiAgent}
            >
              <Send className="h-4 w-4" />
              Create Quote
            </Button>
          </LockedFeature>
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
