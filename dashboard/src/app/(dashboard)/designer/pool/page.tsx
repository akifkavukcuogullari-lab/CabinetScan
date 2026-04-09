'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { formatDistanceToNow } from 'date-fns'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Inbox,
  Loader2,
  BoxSelect,
  AlertTriangle,
  RefreshCw,
} from 'lucide-react'

interface PoolProject {
  id: string // project id
  reference_number: string
  project_name: string | null
  design_request_id: string
  design_status: string
  priority: string
  design_notes: string | null
  request_created_at: string
}

const priorityConfig: Record<string, { label: string; className: string }> = {
  urgent: { label: 'Urgent', className: 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300' },
  high: { label: 'High', className: 'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300' },
  normal: { label: 'Normal', className: 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300' },
  low: { label: 'Low', className: 'bg-gray-100 text-gray-800 dark:bg-gray-800/40 dark:text-gray-300' },
}

export default function DesignPoolPage() {
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [projects, setProjects] = useState<PoolProject[]>([])
  const [acceptingId, setAcceptingId] = useState<string | null>(null)
  const [designerId, setDesignerId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const loadPool = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      // Get current user and designer ID
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/login')
        return
      }

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

      setDesignerId(designer.id)

      // Fetch pending design requests from the view
      const { data, error: fetchError } = await supabase
        .from('designer_project_view')
        .select('id, reference_number, project_name, design_request_id, design_status, priority, design_notes, request_created_at')
        .eq('design_status', 'pending')
        .order('request_created_at', { ascending: false })

      if (fetchError) {
        setError(fetchError.message)
      } else {
        setProjects(data || [])
      }
    } catch (err) {
      setError('Failed to load design pool')
    } finally {
      setLoading(false)
    }
  }, [supabase, router])

  useEffect(() => {
    loadPool()
  }, [loadPool])

  const handleAccept = async (designRequestId: string) => {
    if (!designerId || acceptingId) return

    setAcceptingId(designRequestId)

    try {
      const { data, error } = await supabase
        .from('design_requests')
        .update({
          designer_id: designerId,
          status: 'accepted',
          accepted_at: new Date().toISOString(),
        })
        .eq('id', designRequestId)
        .eq('status', 'pending') // optimistic locking
        .select()

      if (error) {
        toast.error('Failed to accept request: ' + error.message)
        setAcceptingId(null)
        return
      }

      if (!data || data.length === 0) {
        toast.error('This request has already been claimed by another designer')
        // Refresh the list to remove stale entries
        loadPool()
        setAcceptingId(null)
        return
      }

      toast.success('Design request accepted!')
      router.push(`/designer/projects/${designRequestId}`)
    } catch {
      toast.error('Something went wrong. Please try again.')
      setAcceptingId(null)
    }
  }

  if (loading) {
    return (
      <div className="max-w-full space-y-6">
        <div>
          <h1 className="text-2xl font-bold">Design Pool</h1>
          <p className="text-muted-foreground">Available design requests waiting for a designer</p>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="p-4 space-y-3">
                <Skeleton className="h-36 w-full rounded-md" />
                <div className="flex items-center gap-2">
                  <Skeleton className="h-5 w-24" />
                  <Skeleton className="h-5 w-16" />
                </div>
                <Skeleton className="h-5 w-3/4" />
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-2/3" />
                <Skeleton className="h-9 w-full" />
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-full space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Design Pool</h1>
          <p className="text-muted-foreground">
            Available design requests waiting for a designer
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={loadPool}
          className="gap-2"
        >
          <RefreshCw className="h-4 w-4" />
          Refresh
        </Button>
      </div>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center">
            <AlertTriangle className="h-8 w-8 text-red-500 mx-auto mb-3" />
            <p className="text-red-600 dark:text-red-400">Error loading pool: {error}</p>
            <Button variant="outline" size="sm" className="mt-4" onClick={loadPool}>
              Try again
            </Button>
          </CardContent>
        </Card>
      ) : projects.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center">
            <div className="w-20 h-20 rounded-full bg-muted flex items-center justify-center mx-auto mb-6">
              <Inbox className="h-10 w-10 text-muted-foreground" />
            </div>
            <h3 className="text-xl font-medium mb-2">No pending design requests</h3>
            <p className="text-muted-foreground max-w-md mx-auto">
              There are no design requests waiting in the pool at the moment. Check back later or refresh to see new requests.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {projects.map((project) => {
            const priority = priorityConfig[project.priority] || priorityConfig.normal
            const isAccepting = acceptingId === project.design_request_id

            return (
              <Card key={project.design_request_id} className="flex flex-col hover:shadow-md transition-shadow">
                <CardContent className="p-4 flex flex-col flex-1">
                  {/* Placeholder thumbnail */}
                  <div className="h-36 w-full rounded-md bg-muted flex items-center justify-center mb-3">
                    <BoxSelect className="h-12 w-12 text-muted-foreground/50" />
                  </div>

                  {/* Reference + Priority */}
                  <div className="flex items-center gap-2 mb-2">
                    <Badge variant="secondary" className="font-mono text-xs">
                      {project.reference_number}
                    </Badge>
                    <Badge className={priority.className}>
                      {priority.label}
                    </Badge>
                  </div>

                  {/* Reference Only - no customer/project name */}
                  <h3 className="font-semibold text-foreground truncate mb-1">
                    Project {project.reference_number}
                  </h3>

                  {/* Date posted */}
                  <p className="text-xs text-muted-foreground mb-2">
                    Posted {formatDistanceToNow(new Date(project.request_created_at), { addSuffix: true })}
                  </p>

                  {/* Design notes */}
                  {project.design_notes ? (
                    <p className="text-sm text-muted-foreground line-clamp-2 mb-4 flex-1">
                      {project.design_notes}
                    </p>
                  ) : (
                    <p className="text-sm text-muted-foreground/60 italic mb-4 flex-1">
                      No design brief provided
                    </p>
                  )}

                  {/* Accept button */}
                  <Button
                    className="w-full mt-auto"
                    onClick={() => handleAccept(project.design_request_id)}
                    disabled={isAccepting || !!acceptingId}
                  >
                    {isAccepting ? (
                      <>
                        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                        Accepting...
                      </>
                    ) : (
                      'Accept Request'
                    )}
                  </Button>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
