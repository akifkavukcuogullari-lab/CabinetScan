'use client'

import { ProjectSidebar } from './ProjectSidebar'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useSubscriptionContextOptional } from '@/contexts/subscription-context'
import { createClient } from '@/lib/supabase/client'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'

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
  usdz_file_url?: string
  video_url?: string
  preview_image_url?: string
  visualization_photo_urls?: string[]
  measurements?: any
  new_design_svg_url?: string
}

interface ProjectSidebarWrapperProps {
  project: Project
  measurement?: Measurement | null
  canExportDxf?: boolean
  visualizeKitchenEnabled?: boolean
  onStatusChange: (status: string) => Promise<void>
  onCreateQuote?: () => Promise<void>
  onDeleteProject?: () => Promise<void>
}

export function ProjectSidebarWrapper({
  project,
  measurement,
  canExportDxf,
  visualizeKitchenEnabled = false,
  onStatusChange,
  onCreateQuote,
  onDeleteProject
}: ProjectSidebarWrapperProps) {
  const router = useRouter()
  const subscription = useSubscriptionContextOptional()
  const [isVisualizing, setIsVisualizing] = useState(false)
  const [isCreatingQuote, setIsCreatingQuote] = useState(false)
  const [quoteError, setQuoteError] = useState<string | null>(null)
  const [isRequestingRestore, setIsRequestingRestore] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)

  const currentPlan = subscription?.subscription?.plan || null

  const handleVisualizeKitchen = async () => {
    try {
      setIsVisualizing(true)

      // TODO: Replace with actual microservice endpoint
      const response = await fetch('/api/visualize-kitchen', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          project_id: project.id,
          measurements: measurement?.measurements,
          reference_number: project.reference_number
        }),
      })

      if (!response.ok) {
        throw new Error('Failed to visualize kitchen')
      }

      const data = await response.json()

      // Handle the response - could open in new tab, show modal, etc.
      if (data.visualization_url) {
        window.open(data.visualization_url, '_blank')
      }

      router.refresh()
    } catch (error) {
      console.error('Error visualizing kitchen:', error)
      alert('Failed to generate kitchen visualization. Please try again.')
    } finally {
      setIsVisualizing(false)
    }
  }

  const handleRequestRestore = async () => {
    try {
      setIsRequestingRestore(true)
      const supabase = createClient()

      // Get session for auth token
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        throw new Error('Not authenticated')
      }

      // Call the restore Edge Function
      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/restore-project-files`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`
          },
          body: JSON.stringify({
            project_id: project.id,
            restore_tier: 'Expedited'
          })
        }
      )

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to request restore')
      }

      router.refresh()
    } catch (error) {
      console.error('Error requesting restore:', error)
      alert('Failed to request file restore. Please try again.')
    } finally {
      setIsRequestingRestore(false)
    }
  }

  const handleCreateQuote = async () => {
    if (!onCreateQuote) return

    try {
      setIsCreatingQuote(true)
      setQuoteError(null)

      // Trigger the webhook
      await onCreateQuote()

      // Poll for quote email to appear (n8n takes a few seconds to process)
      const supabase = createClient()
      const maxAttempts = 15 // 15 attempts * 2 seconds = 30 seconds max
      let attempts = 0

      const pollForQuote = async (): Promise<boolean> => {
        const { data } = await supabase
          .from('quote_emails')
          .select('id')
          .eq('project_id', project.id)
          .order('created_at', { ascending: false })
          .limit(1)

        return data && data.length > 0
      }

      // Wait a moment for n8n to start processing
      await new Promise(resolve => setTimeout(resolve, 2000))

      while (attempts < maxAttempts) {
        const found = await pollForQuote()
        if (found) {
          setQuoteError(null)
          router.refresh()
          return
        }
        await new Promise(resolve => setTimeout(resolve, 2000))
        attempts++
      }

      // If we get here, quote wasn't found in time - show error
      setQuoteError('Quote generation timed out. The AI service may be busy or unavailable.')
    } catch (error) {
      console.error('Error creating quote:', error)
      setQuoteError('Failed to generate quote. Please check your connection and try again.')
    } finally {
      setIsCreatingQuote(false)
    }
  }

  const handleDeleteProject = async () => {
    if (!onDeleteProject) return

    try {
      setIsDeleting(true)
      await onDeleteProject()
      router.push('/showroom/projects')
    } catch (error) {
      console.error('Error deleting project:', error)
      alert('Failed to delete project. Please try again.')
    } finally {
      setIsDeleting(false)
      setShowDeleteConfirm(false)
    }
  }

  return (
    <>
      <AlertDialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Project?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete this project and all associated data including:
              <ul className="list-disc list-inside mt-2 space-y-1">
                <li>3D room scan (USDZ file)</li>
                <li>Scan video recording</li>
                <li>Photos and visualizations</li>
                <li>Floor plan measurements</li>
                <li>Product selections</li>
                <li>Quote emails</li>
              </ul>
              <p className="mt-3 font-medium text-red-600">This action cannot be undone.</p>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteProject}
              disabled={isDeleting}
              className="bg-red-600 hover:bg-red-700"
            >
              {isDeleting ? 'Deleting...' : 'Delete Project'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <ProjectSidebar
        project={project}
        measurement={measurement}
        canExportDxf={canExportDxf}
        visualizeKitchenEnabled={visualizeKitchenEnabled}
        currentPlan={currentPlan}
        onStatusChange={onStatusChange}
        onCreateQuote={handleCreateQuote}
        onVisualizeKitchen={handleVisualizeKitchen}
        isCreatingQuote={isCreatingQuote}
        quoteError={quoteError}
        onDismissQuoteError={() => setQuoteError(null)}
        onRequestRestore={handleRequestRestore}
        isRequestingRestore={isRequestingRestore}
        onDeleteProject={() => setShowDeleteConfirm(true)}
        isDeleting={isDeleting}
      />
    </>
  )
}
