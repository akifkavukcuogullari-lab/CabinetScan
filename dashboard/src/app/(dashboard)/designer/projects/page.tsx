'use client'

import { useState, useEffect, useMemo, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { formatDistanceToNow } from 'date-fns'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { Input } from '@/components/ui/input'
import {
  FolderKanban,
  Loader2,
  Search,
  AlertTriangle,
  MessageCircle,
  BoxSelect,
  Clock,
  Image as ImageIcon,
} from 'lucide-react'

interface DesignerProject {
  id: string // project id
  reference_number: string
  project_name: string | null
  design_request_id: string
  design_status: string
  priority: string
  design_notes: string | null
  designer_id: string
  accepted_at: string | null
  estimated_completion_at: string | null
  request_created_at: string
  preview_image_url?: string | null
  unread_count?: number
}

const statusTabs = [
  { value: 'all', label: 'All' },
  { value: 'accepted', label: 'Accepted' },
  { value: 'in_progress', label: 'In Progress' },
  { value: 'delivered', label: 'Delivered' },
  { value: 'revision_requested', label: 'Revision' },
  { value: 'completed', label: 'Completed' },
]

const statusConfig: Record<string, { label: string; className: string }> = {
  accepted: { label: 'Accepted', className: 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300' },
  in_progress: { label: 'In Progress', className: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-300' },
  delivered: { label: 'Delivered', className: 'bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300' },
  revision_requested: { label: 'Revision', className: 'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300' },
  approved: { label: 'Approved', className: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300' },
  completed: { label: 'Completed', className: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300' },
  canceled: { label: 'Canceled', className: 'bg-gray-100 text-gray-800 dark:bg-gray-800/40 dark:text-gray-300' },
}

const priorityConfig: Record<string, { label: string; className: string }> = {
  urgent: { label: 'Urgent', className: 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300' },
  high: { label: 'High', className: 'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300' },
  normal: { label: 'Normal', className: 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300' },
  low: { label: 'Low', className: 'bg-gray-100 text-gray-800 dark:bg-gray-800/40 dark:text-gray-300' },
}

export default function DesignerProjectsPage() {
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [projects, setProjects] = useState<DesignerProject[]>([])
  const [error, setError] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState('all')
  const [searchQuery, setSearchQuery] = useState('')

  const loadProjects = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/login')
        return
      }

      // Get designer ID
      const { data: designer } = await supabase
        .from('designers')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .single()

      if (!designer) {
        router.push('/login')
        return
      }

      // Fetch designer's assigned projects (non-pending) from the view
      const { data: projectData, error: fetchError } = await supabase
        .from('designer_project_view')
        .select('id, reference_number, project_name, design_request_id, design_status, priority, design_notes, designer_id, accepted_at, estimated_completion_at, request_created_at')
        .eq('designer_id', designer.id)
        .neq('design_status', 'pending')
        .order('accepted_at', { ascending: false })

      if (fetchError) {
        setError(fetchError.message)
        setLoading(false)
        return
      }

      const projectList: DesignerProject[] = projectData || []

      if (projectList.length === 0) {
        setProjects([])
        setLoading(false)
        return
      }

      // Fetch preview images from project_measurements
      const projectIds = projectList.map((p) => p.id)
      const { data: measurements } = await supabase
        .from('project_measurements')
        .select('project_id, preview_image_url')
        .in('project_id', projectIds)

      const previewMap = new Map<string, string>()
      if (measurements) {
        for (const m of measurements) {
          if (m.preview_image_url && !previewMap.has(m.project_id)) {
            previewMap.set(m.project_id, m.preview_image_url)
          }
        }
      }

      // Fetch unread chat message counts per design request
      const designRequestIds = projectList.map((p) => p.design_request_id)
      const { data: unreadMessages } = await supabase
        .from('design_chat_messages')
        .select('design_request_id')
        .in('design_request_id', designRequestIds)
        .eq('sender_type', 'showroom')
        .eq('is_read', false)

      const unreadMap = new Map<string, number>()
      if (unreadMessages) {
        for (const msg of unreadMessages) {
          unreadMap.set(msg.design_request_id, (unreadMap.get(msg.design_request_id) || 0) + 1)
        }
      }

      // Merge data
      const enriched = projectList.map((p) => ({
        ...p,
        preview_image_url: previewMap.get(p.id) || null,
        unread_count: unreadMap.get(p.design_request_id) || 0,
      }))

      setProjects(enriched)
    } catch {
      setError('Failed to load projects')
    } finally {
      setLoading(false)
    }
  }, [supabase, router])

  useEffect(() => {
    loadProjects()
  }, [loadProjects])

  // Filter projects by active tab and search
  const filteredProjects = useMemo(() => {
    return projects.filter((p) => {
      if (activeTab !== 'all' && p.design_status !== activeTab) return false

      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase()
        const ref = (p.reference_number || '').toLowerCase()
        if (!ref.includes(q)) return false
      }

      return true
    })
  }, [projects, activeTab, searchQuery])

  // Count per status tab
  const statusCounts = useMemo(() => {
    const counts: Record<string, number> = { all: projects.length }
    for (const p of projects) {
      counts[p.design_status] = (counts[p.design_status] || 0) + 1
    }
    return counts
  }, [projects])

  if (loading) {
    return (
      <div className="max-w-full space-y-6">
        <div>
          <h1 className="text-2xl font-bold">My Projects</h1>
          <p className="text-muted-foreground">Design projects you are working on</p>
        </div>
        {/* Skeleton tabs */}
        <div className="flex gap-2 overflow-x-auto pb-1">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-9 w-24 rounded-md" />
          ))}
        </div>
        {/* Skeleton cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="p-4 space-y-3">
                <Skeleton className="h-36 w-full rounded-md" />
                <div className="flex items-center gap-2">
                  <Skeleton className="h-5 w-24" />
                  <Skeleton className="h-5 w-16" />
                  <Skeleton className="h-5 w-20" />
                </div>
                <Skeleton className="h-5 w-3/4" />
                <Skeleton className="h-4 w-1/2" />
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-full space-y-6">
      <div>
        <h1 className="text-2xl font-bold">My Projects</h1>
        <p className="text-muted-foreground">Design projects you are working on</p>
      </div>

      {/* Search */}
      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Search by name or reference..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="pl-10"
        />
      </div>

      {/* Status filter tabs */}
      <div className="flex gap-2 overflow-x-auto pb-1">
        {statusTabs.map((tab) => {
          const count = statusCounts[tab.value] || 0
          const isActive = activeTab === tab.value

          return (
            <Button
              key={tab.value}
              variant={isActive ? 'default' : 'outline'}
              size="sm"
              onClick={() => setActiveTab(tab.value)}
              className="gap-2 shrink-0"
            >
              {tab.label}
              {count > 0 && (
                <Badge
                  variant={isActive ? 'secondary' : 'outline'}
                  className="text-xs px-1.5 py-0"
                >
                  {count}
                </Badge>
              )}
            </Button>
          )
        })}
      </div>

      {/* Content */}
      {error ? (
        <Card>
          <CardContent className="py-10 text-center">
            <AlertTriangle className="h-8 w-8 text-red-500 mx-auto mb-3" />
            <p className="text-red-600 dark:text-red-400">Error loading projects: {error}</p>
            <Button variant="outline" size="sm" className="mt-4" onClick={loadProjects}>
              Try again
            </Button>
          </CardContent>
        </Card>
      ) : filteredProjects.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center">
            <div className="w-20 h-20 rounded-full bg-muted flex items-center justify-center mx-auto mb-6">
              <FolderKanban className="h-10 w-10 text-muted-foreground" />
            </div>
            <h3 className="text-xl font-medium mb-2">
              {projects.length === 0
                ? 'No projects yet'
                : 'No projects with this status'}
            </h3>
            <p className="text-muted-foreground max-w-md mx-auto">
              {projects.length === 0
                ? 'Accept requests from the Design Pool to start working on projects.'
                : 'Try selecting a different status filter or adjusting your search.'}
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {filteredProjects.map((project) => {
            const status = statusConfig[project.design_status] || statusConfig.accepted
            const priority = priorityConfig[project.priority] || priorityConfig.normal

            return (
              <Card
                key={project.design_request_id}
                className="cursor-pointer hover:shadow-md transition-shadow group relative"
                onClick={() => router.push(`/designer/projects/${project.design_request_id}`)}
              >
                <CardContent className="p-4">
                  {/* Unread indicator */}
                  {project.unread_count && project.unread_count > 0 ? (
                    <div className="absolute top-3 right-3 z-10 flex items-center gap-1 bg-red-500 text-white rounded-full px-2 py-0.5 text-xs font-medium">
                      <MessageCircle className="h-3 w-3" />
                      {project.unread_count}
                    </div>
                  ) : null}

                  {/* Thumbnail */}
                  <div className="h-36 w-full rounded-md bg-muted mb-3 overflow-hidden">
                    {project.preview_image_url ? (
                      <img
                        src={project.preview_image_url}
                        alt="Room preview"
                        className="w-full h-full object-cover"
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <BoxSelect className="h-12 w-12 text-muted-foreground/50" />
                      </div>
                    )}
                  </div>

                  {/* Badges row */}
                  <div className="flex items-center gap-2 flex-wrap mb-2">
                    <Badge variant="secondary" className="font-mono text-xs">
                      {project.reference_number}
                    </Badge>
                    <Badge className={status.className}>
                      {status.label}
                    </Badge>
                    <Badge className={priority.className}>
                      {priority.label}
                    </Badge>
                  </div>

                  {/* Reference Only */}
                  <h3 className="font-semibold text-foreground truncate group-hover:text-blue-600 dark:group-hover:text-blue-400 transition-colors">
                    Project {project.reference_number}
                  </h3>

                  {/* Accepted date */}
                  <p className="text-xs text-muted-foreground mt-1">
                    Accepted{' '}
                    {project.accepted_at
                      ? formatDistanceToNow(new Date(project.accepted_at), { addSuffix: true })
                      : 'recently'}
                  </p>

                  {/* Remaining time */}
                  {project.estimated_completion_at && !['completed', 'canceled'].includes(project.design_status) && (() => {
                    const now = new Date()
                    const deadline = new Date(project.estimated_completion_at)
                    const diffMs = deadline.getTime() - now.getTime()
                    const isOverdue = diffMs < 0
                    const absDiffMs = Math.abs(diffMs)
                    const days = Math.floor(absDiffMs / (1000 * 60 * 60 * 24))
                    const hours = Math.floor((absDiffMs % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))

                    let timeText = ''
                    if (days > 0) timeText = `${days}d ${hours}h`
                    else if (hours > 0) timeText = `${hours}h`
                    else timeText = 'Less than 1h'

                    return (
                      <div className={`mt-2 px-2 py-1.5 rounded-md text-xs font-medium flex items-center gap-1.5 ${
                        isOverdue
                          ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'
                          : days === 0
                            ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                            : 'bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                      }`}>
                        <Clock className="h-3 w-3" />
                        {isOverdue ? `Overdue by ${timeText}` : `${timeText} remaining`}
                      </div>
                    )
                  })()}
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
