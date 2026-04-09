import { createClient } from '@/lib/supabase/server'
import { notFound } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { ArrowLeft, FolderKanban, CheckCircle2, MessageSquare, User } from 'lucide-react'

interface DesignerDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function DesignerDetailPage({ params }: DesignerDetailPageProps) {
  const { id } = await params
  const supabase = await createClient()

  // Fetch designer
  const { data: designer, error } = await supabase
    .from('designers')
    .select('*')
    .eq('id', id)
    .single()

  if (error || !designer) {
    notFound()
  }

  // Fetch design requests with project info
  const { data: requests } = await supabase
    .from('design_requests')
    .select('id, status, project_id, accepted_at, delivered_at, completed_at, created_at, projects(reference_number, project_name)')
    .eq('designer_id', id)
    .order('created_at', { ascending: false })

  // Count stats
  const activeCount = requests?.filter(
    (r: { status: string }) => !['completed', 'canceled'].includes(r.status)
  ).length || 0
  const completedCount = requests?.filter(
    (r: { status: string }) => r.status === 'completed'
  ).length || 0

  // Message count
  const { count: messageCount } = await supabase
    .from('design_chat_messages')
    .select('*', { count: 'exact', head: true })
    .eq('sender_type', 'designer')
    .eq('sender_id', id)

  const statusColors: Record<string, string> = {
    pending: 'bg-yellow-50 text-yellow-700 border-yellow-200',
    accepted: 'bg-blue-50 text-blue-700 border-blue-200',
    in_progress: 'bg-purple-50 text-purple-700 border-purple-200',
    delivered: 'bg-indigo-50 text-indigo-700 border-indigo-200',
    revision_requested: 'bg-orange-50 text-orange-700 border-orange-200',
    completed: 'bg-green-50 text-green-700 border-green-200',
    canceled: 'bg-gray-50 text-gray-600 border-gray-200',
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Link href="/admin/designers">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold">{designer.full_name}</h1>
            {designer.is_active ? (
              <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
                Active
              </Badge>
            ) : (
              <Badge variant="outline" className="bg-gray-50 text-gray-600 border-gray-200">
                Inactive
              </Badge>
            )}
          </div>
          <p className="text-gray-500">{designer.email}</p>
        </div>
        <Link href={`/admin/designers/${id}/edit`}>
          <Button variant="outline">Edit Designer</Button>
        </Link>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-blue-100 rounded-lg">
                <FolderKanban className="h-6 w-6 text-blue-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{activeCount}</p>
                <p className="text-sm text-gray-500">Active Projects</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-green-100 rounded-lg">
                <CheckCircle2 className="h-6 w-6 text-green-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{completedCount}</p>
                <p className="text-sm text-gray-500">Completed Projects</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-purple-100 rounded-lg">
                <MessageSquare className="h-6 w-6 text-purple-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{messageCount || 0}</p>
                <p className="text-sm text-gray-500">Total Messages</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Profile Card */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <User className="h-5 w-5" />
            Profile
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-start gap-6">
            {designer.avatar_url ? (
              <img
                src={designer.avatar_url}
                alt={designer.full_name}
                className="h-20 w-20 rounded-full object-cover border-2 border-gray-100"
              />
            ) : (
              <div className="h-20 w-20 rounded-full bg-gray-100 flex items-center justify-center">
                <User className="h-10 w-10 text-gray-400" />
              </div>
            )}
            <div className="flex-1 space-y-3">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-gray-500">Full Name</p>
                  <p className="font-medium">{designer.full_name}</p>
                </div>
                <div>
                  <p className="text-sm text-gray-500">Email</p>
                  <p className="font-medium">{designer.email}</p>
                </div>
              </div>
              <div>
                <p className="text-sm text-gray-500">Bio</p>
                <p className="text-gray-700">{designer.bio || 'No bio provided'}</p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Joined</p>
                <p>{new Date(designer.created_at).toLocaleDateString('en-US', {
                  year: 'numeric',
                  month: 'long',
                  day: 'numeric',
                })}</p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Project History */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <FolderKanban className="h-5 w-5" />
            Project History
          </CardTitle>
        </CardHeader>
        <CardContent>
          {requests && requests.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Project</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Accepted</TableHead>
                  <TableHead>Delivered</TableHead>
                  <TableHead>Completed</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map((request: {
                  id: string
                  status: string
                  project_id: string
                  accepted_at: string | null
                  delivered_at: string | null
                  completed_at: string | null
                  created_at: string
                  projects: { reference_number: string; project_name: string } | null
                }) => (
                  <TableRow key={request.id}>
                    <TableCell>
                      <div>
                        <p className="font-medium">
                          {request.projects?.project_name || 'Untitled Project'}
                        </p>
                        <p className="text-xs text-gray-500">
                          {request.projects?.reference_number || request.project_id}
                        </p>
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline" className={statusColors[request.status] || 'bg-gray-50 text-gray-600 border-gray-200'}>
                        {request.status.replace(/_/g, ' ')}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-gray-500 text-sm">
                      {request.accepted_at
                        ? new Date(request.accepted_at).toLocaleDateString()
                        : '-'}
                    </TableCell>
                    <TableCell className="text-gray-500 text-sm">
                      {request.delivered_at
                        ? new Date(request.delivered_at).toLocaleDateString()
                        : '-'}
                    </TableCell>
                    <TableCell className="text-gray-500 text-sm">
                      {request.completed_at
                        ? new Date(request.completed_at).toLocaleDateString()
                        : '-'}
                    </TableCell>
                    <TableCell className="text-gray-500 text-sm">
                      {new Date(request.created_at).toLocaleDateString()}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <div className="py-8 text-center text-gray-500">
              <FolderKanban className="h-8 w-8 mx-auto mb-2 text-gray-300" />
              <p>No project history yet</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
