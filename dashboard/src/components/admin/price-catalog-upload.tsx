'use client'

import { useState, useRef, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Loader2,
  Upload,
  FileSpreadsheet,
  Trash2,
  Database,
  CheckCircle2,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'

interface PriceCatalogUploadProps {
  showroom: {
    id: string
    name: string
  }
}

export function PriceCatalogUpload({ showroom }: PriceCatalogUploadProps) {
  const router = useRouter()
  const supabase = createClient()
  const fileInputRef = useRef<HTMLInputElement>(null)

  const [uploading, setUploading] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [entryCount, setEntryCount] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)

  // Fetch current entry count on mount
  useEffect(() => {
    async function fetchEntryCount() {
      setLoading(true)
      try {
        const { count, error } = await supabase
          .from('price_catalog')
          .select('*', { count: 'exact', head: true })
          .eq('showroom_id', showroom.id)

        if (!error && count !== null) {
          setEntryCount(count)
        }
      } catch (error) {
        console.error('Error fetching entry count:', error)
      } finally {
        setLoading(false)
      }
    }

    fetchEntryCount()
  }, [showroom.id, supabase])

  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    // Validate file type
    if (!file.name.toLowerCase().endsWith('.csv')) {
      toast.error('Please select a CSV file')
      return
    }

    // Validate file size (10MB max)
    if (file.size > 10 * 1024 * 1024) {
      toast.error('File size must be less than 10MB')
      return
    }

    setUploading(true)

    try {
      // Read file content
      const csvContent = await file.text()

      // Call Edge Function to process and embed
      toast.info('Processing catalog and generating embeddings...')

      const { data: { session } } = await supabase.auth.getSession()

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/upload-price-catalog`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session?.access_token}`,
          },
          body: JSON.stringify({
            showroom_id: showroom.id,
            csv_content: csvContent,
          }),
        }
      )

      const result = await response.json()

      if (!response.ok) {
        throw new Error(result.error || 'Failed to upload catalog')
      }

      setEntryCount(result.row_count)
      toast.success(`Successfully uploaded ${result.row_count} catalog entries`)
      router.refresh()
    } catch (error) {
      console.error('Upload error:', error)
      toast.error(error instanceof Error ? error.message : 'Failed to upload catalog')
    } finally {
      setUploading(false)
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const handleDelete = async () => {
    if (entryCount === 0 || entryCount === null) return

    setDeleting(true)

    try {
      // Delete all entries for this showroom
      const { error: deleteError } = await supabase
        .from('price_catalog')
        .delete()
        .eq('showroom_id', showroom.id)

      if (deleteError) {
        console.error('Delete error:', deleteError)
        toast.error('Failed to remove catalog: ' + deleteError.message)
        return
      }

      setEntryCount(0)
      toast.success('Price catalog removed')
      router.refresh()
    } catch (error) {
      console.error('Delete error:', error)
      toast.error('Failed to remove catalog')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Database className="h-5 w-5" />
          Price Catalog
        </CardTitle>
        <CardDescription>
          Upload a CSV price catalog for this showroom. Used by AI agent for price lookups.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Current Catalog Status */}
        {loading ? (
          <div className="flex items-center gap-2 p-4 bg-gray-50 border rounded-lg">
            <Loader2 className="h-5 w-5 animate-spin text-gray-500" />
            <span className="text-gray-600">Loading catalog status...</span>
          </div>
        ) : entryCount !== null && entryCount > 0 ? (
          <div className="flex items-center justify-between p-4 bg-green-50 border border-green-200 rounded-lg">
            <div className="flex items-center gap-3">
              <CheckCircle2 className="h-8 w-8 text-green-600" />
              <div>
                <p className="font-medium text-green-900">Catalog Active</p>
                <p className="text-sm text-green-700">
                  {entryCount} items indexed for semantic search
                </p>
              </div>
            </div>
            <Button
              variant="destructive"
              size="sm"
              onClick={handleDelete}
              disabled={deleting}
            >
              {deleting ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <>
                  <Trash2 className="h-4 w-4 mr-1" />
                  Remove
                </>
              )}
            </Button>
          </div>
        ) : (
          <div className="flex items-center gap-3 p-4 bg-gray-50 border rounded-lg">
            <FileSpreadsheet className="h-8 w-8 text-gray-400" />
            <div>
              <p className="font-medium text-gray-700">No Catalog</p>
              <p className="text-sm text-gray-500">
                Upload a CSV to enable AI price lookups
              </p>
            </div>
          </div>
        )}

        {/* Upload Area */}
        <div
          className={`
            border-2 border-dashed rounded-lg p-8 text-center transition-colors
            ${entryCount && entryCount > 0 ? 'border-gray-200 bg-gray-50' : 'border-blue-300 bg-blue-50 hover:bg-blue-100'}
          `}
        >
          <input
            type="file"
            ref={fileInputRef}
            accept=".csv"
            onChange={handleFileSelect}
            className="hidden"
            disabled={uploading}
          />

          <FileSpreadsheet className="h-12 w-12 mx-auto mb-4 text-gray-400" />

          <p className="text-gray-600 mb-2">
            {entryCount && entryCount > 0
              ? 'Upload a new catalog to replace the existing one'
              : 'Upload a CSV price catalog'}
          </p>

          <p className="text-sm text-gray-500 mb-4">
            CSV format: type, size, style, color, price
          </p>

          <Button
            onClick={() => fileInputRef.current?.click()}
            disabled={uploading}
            variant={entryCount && entryCount > 0 ? 'outline' : 'default'}
          >
            {uploading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Uploading...
              </>
            ) : (
              <>
                <Upload className="h-4 w-4 mr-2" />
                {entryCount && entryCount > 0 ? 'Replace Catalog' : 'Upload Catalog'}
              </>
            )}
          </Button>
        </div>

        {/* Info */}
        <div className="text-sm text-gray-500 space-y-1">
          <p>
            <strong>Max size:</strong> 10MB
          </p>
          <p>
            <strong>How it works:</strong> CSV data is parsed and stored in Supabase. Each showroom has its own catalog.
          </p>
          <p>
            <strong>Usage:</strong> AI agents query the <code className="bg-gray-100 px-1 rounded">price_catalog</code> table directly.
          </p>
        </div>
      </CardContent>
    </Card>
  )
}
