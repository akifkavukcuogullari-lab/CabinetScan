'use client'

import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { MessageCircle, ChevronDown, ChevronUp } from 'lucide-react'
import ProjectChat from '@/components/project/ProjectChat'

interface ProjectChatWrapperProps {
  projectId: string
  showroomId: string
  currentUserId: string
  currentUserName: string
  currentUserRole: string
}

export function ProjectChatWrapper({
  projectId,
  showroomId,
  currentUserId,
  currentUserName,
  currentUserRole,
}: ProjectChatWrapperProps) {
  const [isExpanded, setIsExpanded] = useState(false)

  return (
    <Card>
      <CardContent className="p-0">
        <Button
          variant="ghost"
          className="w-full flex items-center justify-between p-4 hover:bg-gray-50 rounded-lg"
          onClick={() => setIsExpanded(!isExpanded)}
        >
          <div className="flex items-center gap-2">
            <MessageCircle className="h-4 w-4 text-blue-500" />
            <span className="font-semibold text-sm">Project Chat</span>
            <span className="text-xs text-muted-foreground">(with staff)</span>
          </div>
          {isExpanded ? (
            <ChevronUp className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          )}
        </Button>

        {isExpanded && (
          <div className="border-t">
            <ProjectChat
              projectId={projectId}
              showroomId={showroomId}
              currentUserId={currentUserId}
              currentUserName={currentUserName}
              currentUserRole={currentUserRole}
            />
          </div>
        )}
      </CardContent>
    </Card>
  )
}
