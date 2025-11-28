import { createClient } from '@/lib/supabase/server'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { FolderKanban } from 'lucide-react'
import Link from 'next/link'
import { redirect } from 'next/navigation'

export default async function ProjectsPage() {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get the user's showroom
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('showroom_id')
    .eq('user_id', user.id)
    .single()

  if (!showroomUser) redirect('/login')

  const { data: projects, error } = await supabase
    .from('projects')
    .select('*')
    .eq('showroom_id', showroomUser.showroom_id)
    .order('submitted_at', { ascending: false })

  const statusColors: Record<string, string> = {
    draft: 'bg-gray-100 text-gray-800',
    submitted: 'bg-blue-100 text-blue-800',
    in_review: 'bg-yellow-100 text-yellow-800',
    quoted: 'bg-purple-100 text-purple-800',
    accepted: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800',
    completed: 'bg-green-100 text-green-800',
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Projects</h1>
        <p className="text-gray-500">View and manage customer submissions</p>
      </div>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center text-red-600">
            Error loading projects: {error.message}
          </CardContent>
        </Card>
      ) : projects && projects.length > 0 ? (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Reference</TableHead>
                <TableHead>Customer</TableHead>
                <TableHead>Project</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Submitted</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {projects.map((project: any) => (
                <TableRow key={project.id}>
                  <TableCell>
                    <code className="px-2 py-1 bg-gray-100 rounded text-sm font-mono">
                      {project.reference_number}
                    </code>
                  </TableCell>
                  <TableCell>
                    <div>
                      <div className="font-medium">
                        {project.customer_first_name} {project.customer_last_name}
                      </div>
                      <div className="text-sm text-gray-500">
                        {project.customer_email}
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>{project.project_name}</TableCell>
                  <TableCell>
                    <Badge className={statusColors[project.status]}>
                      {project.status.replace('_', ' ')}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {project.submitted_at
                      ? new Date(project.submitted_at).toLocaleDateString()
                      : '-'}
                  </TableCell>
                  <TableCell className="text-right">
                    <Link href={`/showroom/projects/${project.id}`}>
                      <Button variant="ghost" size="sm">
                        View
                      </Button>
                    </Link>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      ) : (
        <Card>
          <CardContent className="py-10 text-center">
            <FolderKanban className="h-12 w-12 mx-auto text-gray-400 mb-4" />
            <h3 className="text-lg font-medium mb-2">No projects yet</h3>
            <p className="text-gray-500">
              Projects will appear here when customers submit scans from the iOS app
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
