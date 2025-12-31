'use client'

import { ProjectSidebar } from './ProjectSidebar'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useSubscriptionContextOptional } from '@/contexts/subscription-context'

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
  usdz_file_url?: string
  video_url?: string
  preview_image_url?: string
  visualization_photo_urls?: string[]
  measurements?: any
}

interface ProjectSidebarWrapperProps {
  project: Project
  measurement?: Measurement | null
  canExportDxf?: boolean
  onStatusChange: (status: string) => Promise<void>
  onCreateQuote?: () => void
}

export function ProjectSidebarWrapper({
  project,
  measurement,
  canExportDxf,
  onStatusChange,
  onCreateQuote
}: ProjectSidebarWrapperProps) {
  const router = useRouter()
  const subscription = useSubscriptionContextOptional()
  const [isVisualizing, setIsVisualizing] = useState(false)

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

  const handleCreateQuote = () => {
    if (onCreateQuote) {
      onCreateQuote()
    }
  }

  return (
    <ProjectSidebar
      project={project}
      measurement={measurement}
      canExportDxf={canExportDxf}
      currentPlan={currentPlan}
      onStatusChange={onStatusChange}
      onCreateQuote={handleCreateQuote}
      onVisualizeKitchen={handleVisualizeKitchen}
    />
  )
}
