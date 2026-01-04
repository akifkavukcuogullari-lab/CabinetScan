import { createClient } from '@/lib/supabase/server'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
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
import { Plus, Building2, Mail, CheckCircle2, Clock, Users } from 'lucide-react'
import Link from 'next/link'

interface ShowroomWithStats {
  id: string
  name: string
  showroom_code: string
  email: string
  subscription_status: string
  created_at: string
  user_count: number
  pending_invitations: number
  has_owner: boolean
}

export default async function ShowroomsPage() {
  const supabase = await createClient()

  // Fetch showrooms
  const { data: showrooms, error } = await supabase
    .from('showrooms')
    .select('*')
    .order('created_at', { ascending: false })

  // Get additional stats for each showroom
  let showroomsWithStats: ShowroomWithStats[] = []

  if (showrooms && showrooms.length > 0) {
    // Get user counts
    const { data: userCounts } = await supabase
      .from('showroom_users')
      .select('showroom_id')
      .eq('is_active', true)

    // Get pending invitations
    const { data: pendingInvites } = await supabase
      .from('showroom_invitations')
      .select('showroom_id, status')
      .eq('status', 'pending')

    // Build stats map
    const userCountMap: Record<string, number> = {}
    const pendingInviteMap: Record<string, number> = {}

    userCounts?.forEach((u: { showroom_id: string }) => {
      userCountMap[u.showroom_id] = (userCountMap[u.showroom_id] || 0) + 1
    })

    pendingInvites?.forEach((i: { showroom_id: string }) => {
      pendingInviteMap[i.showroom_id] = (pendingInviteMap[i.showroom_id] || 0) + 1
    })

    showroomsWithStats = showrooms.map((showroom: {
      id: string
      name: string
      showroom_code: string
      email: string
      subscription_status: string
      created_at: string
    }) => ({
      ...showroom,
      user_count: userCountMap[showroom.id] || 0,
      pending_invitations: pendingInviteMap[showroom.id] || 0,
      has_owner: (userCountMap[showroom.id] || 0) > 0,
    }))
  }

  const statusColors: Record<string, string> = {
    trial: 'bg-yellow-100 text-yellow-800',
    active: 'bg-green-100 text-green-800',
    past_due: 'bg-red-100 text-red-800',
    canceled: 'bg-gray-100 text-gray-800',
    suspended: 'bg-red-100 text-red-800',
  }

  const getOwnerStatusBadge = (showroom: ShowroomWithStats) => {
    if (showroom.has_owner) {
      return (
        <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
          <CheckCircle2 className="h-3 w-3 mr-1" />
          Active
        </Badge>
      )
    } else if (showroom.pending_invitations > 0) {
      return (
        <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">
          <Mail className="h-3 w-3 mr-1" />
          Invited ({showroom.pending_invitations})
        </Badge>
      )
    } else {
      return (
        <Badge variant="outline" className="bg-gray-50 text-gray-600 border-gray-200">
          <Clock className="h-3 w-3 mr-1" />
          No Owner
        </Badge>
      )
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Showrooms</h1>
          <p className="text-gray-500">Manage all showroom tenants</p>
        </div>
        <Link href="/admin/showrooms/new">
          <Button>
            <Plus className="h-4 w-4 mr-2" />
            Add Showroom
          </Button>
        </Link>
      </div>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center text-red-600">
            Error loading showrooms: {error.message}
          </CardContent>
        </Card>
      ) : showroomsWithStats && showroomsWithStats.length > 0 ? (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Code</TableHead>
                <TableHead>Owner Status</TableHead>
                <TableHead>Subscription</TableHead>
                <TableHead>Created</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {showroomsWithStats.map((showroom) => (
                <TableRow key={showroom.id}>
                  <TableCell>
                    <div>
                      <p className="font-medium">{showroom.name}</p>
                      <p className="text-sm text-gray-500">{showroom.email}</p>
                    </div>
                  </TableCell>
                  <TableCell>
                    <code className="px-2 py-1 bg-gray-100 rounded text-sm">
                      {showroom.showroom_code}
                    </code>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      {getOwnerStatusBadge(showroom)}
                      {showroom.user_count > 1 && (
                        <span className="text-xs text-gray-500 flex items-center">
                          <Users className="h-3 w-3 mr-1" />
                          {showroom.user_count}
                        </span>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <Badge className={statusColors[showroom.subscription_status]}>
                      {showroom.subscription_status}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {new Date(showroom.created_at).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="text-right">
                    <Link href={`/admin/showrooms/${showroom.id}`}>
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
            <Building2 className="h-12 w-12 mx-auto text-gray-400 mb-4" />
            <h3 className="text-lg font-medium mb-2">No showrooms yet</h3>
            <p className="text-gray-500 mb-4">
              Create your first showroom to get started
            </p>
            <Link href="/admin/showrooms/new">
              <Button>
                <Plus className="h-4 w-4 mr-2" />
                Add Showroom
              </Button>
            </Link>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
