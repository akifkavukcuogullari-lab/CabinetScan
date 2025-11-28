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
import { Plus, Building2 } from 'lucide-react'
import Link from 'next/link'

export default async function ShowroomsPage() {
  const supabase = await createClient()

  const { data: showrooms, error } = await supabase
    .from('showrooms')
    .select('*')
    .order('created_at', { ascending: false })

  const statusColors: Record<string, string> = {
    trial: 'bg-yellow-100 text-yellow-800',
    active: 'bg-green-100 text-green-800',
    past_due: 'bg-red-100 text-red-800',
    canceled: 'bg-gray-100 text-gray-800',
    suspended: 'bg-red-100 text-red-800',
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
      ) : showrooms && showrooms.length > 0 ? (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Code</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Created</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {showrooms.map((showroom: any) => (
                <TableRow key={showroom.id}>
                  <TableCell className="font-medium">{showroom.name}</TableCell>
                  <TableCell>
                    <code className="px-2 py-1 bg-gray-100 rounded text-sm">
                      {showroom.showroom_code}
                    </code>
                  </TableCell>
                  <TableCell>{showroom.email}</TableCell>
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
