"""Supabase client utilities for the pipeline worker."""

import os
import httpx
from typing import Any


class SupabaseClient:
    """Minimal Supabase client for the pipeline worker.

    Uses service_role key to update job status and upload results.
    """

    def __init__(self):
        self.url = os.environ.get("SUPABASE_URL", "")
        self.service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not self.url or not self.service_key:
            raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.service_key}",
            "Content-Type": "application/json",
            "apikey": self.service_key,
        }

    async def update_job_status(
        self,
        job_id: str,
        status: str | None = None,
        progress: float | None = None,
        stage: str | None = None,
        error_message: str | None = None,
        **kwargs: Any,
    ) -> None:
        """Update a processing job via the update-job-status edge function."""
        body: dict[str, Any] = {"job_id": job_id}
        if status is not None:
            body["status"] = status
        if progress is not None:
            body["progress"] = progress
        if stage is not None:
            body["stage"] = stage
        if error_message is not None:
            body["error_message"] = error_message
        body.update(kwargs)

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.url}/functions/v1/update-job-status",
                json=body,
                headers=self._headers(),
                timeout=30.0,
            )
            resp.raise_for_status()

    async def upload_file(
        self,
        bucket: str,
        path: str,
        data: bytes,
        content_type: str = "application/octet-stream",
    ) -> str:
        """Upload a file to Supabase storage. Returns public URL."""
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.url}/storage/v1/object/{bucket}/{path}",
                content=data,
                headers={
                    "Authorization": f"Bearer {self.service_key}",
                    "Content-Type": content_type,
                },
                timeout=120.0,
            )
            resp.raise_for_status()
        return f"{self.url}/storage/v1/object/public/{bucket}/{path}"

    async def download_file(self, url: str) -> bytes:
        """Download a file from a URL (Supabase storage or other)."""
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, timeout=120.0)
            resp.raise_for_status()
            return resp.content
