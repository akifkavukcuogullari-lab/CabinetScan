'use client'

interface ProjectChatProps {
  projectId: string
  showroomId: string
  currentUserId: string
  currentUserName: string
  currentUserRole: string
}

export default function ProjectChat(_props: ProjectChatProps) {
  return (
    <div className="p-4 text-center text-sm text-muted-foreground">
      Project chat coming soon.
    </div>
  )
}
