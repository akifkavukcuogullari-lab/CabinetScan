'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Paintbrush } from 'lucide-react'
import { DesignRequestModal } from './DesignRequestModal'

interface DesignRequestButtonProps {
  projectId: string
  showroomId: string
  hasExistingRequest: boolean
}

export function DesignRequestButton({
  projectId,
  showroomId,
  hasExistingRequest,
}: DesignRequestButtonProps) {
  const [modalOpen, setModalOpen] = useState(false)

  if (hasExistingRequest) {
    return null
  }

  return (
    <>
      <Button
        variant="outline"
        className="w-full justify-start gap-2"
        onClick={() => setModalOpen(true)}
      >
        <Paintbrush className="h-4 w-4" />
        Request Design
      </Button>
      <DesignRequestModal
        projectId={projectId}
        showroomId={showroomId}
        open={modalOpen}
        onOpenChange={setModalOpen}
      />
    </>
  )
}
