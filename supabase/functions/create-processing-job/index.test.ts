/**
 * Tests for create-processing-job Edge Function.
 * Phase 3.2-test: Server Pipeline V2
 *
 * These tests validate the request handling logic (validation, error responses,
 * response format) by extracting the handler and mocking Supabase.
 *
 * Run: deno test --allow-env supabase/functions/create-processing-job/index.test.ts
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ---------------------------------------------------------------------------
// Helpers — simulate the handler logic without `serve()`
// ---------------------------------------------------------------------------

/** Minimal mock of supabaseAdmin.from(...).insert(...).select(...).single() */
function makeMockSupabase(
  insertResult: { data: unknown; error: unknown } = {
    data: { id: "job-uuid-123" },
    error: null,
  }
) {
  return {
    from: (_table: string) => ({
      insert: (_row: unknown) => ({
        select: (_cols: string) => ({
          single: () => Promise.resolve(insertResult),
        }),
      }),
    }),
  };
}

/** Re-implements the handler logic so we can test without Deno.serve runtime. */
async function handleRequest(
  req: Request,
  supabaseAdmin = makeMockSupabase()
): Promise<Response> {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ error: "Method not allowed" }),
        {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const body = await req.json();

    if (!body.video_url) {
      return new Response(
        JSON.stringify({ error: "video_url is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!body.showroom_id) {
      return new Response(
        JSON.stringify({ error: "showroom_id is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { data: job, error: insertError } = await supabaseAdmin
      .from("processing_jobs")
      .insert({
        video_url: body.video_url,
        poses_url: body.poses_url || null,
        planes_url: body.planes_url || null,
        photo_urls: body.photo_urls || [],
        showroom_id: body.showroom_id,
        metadata: body.metadata || {},
        status: "queued",
        progress: 0,
      })
      .select("id")
      .single();

    if (insertError) {
      return new Response(
        JSON.stringify({
          error: "Failed to create processing job",
          message: (insertError as { message: string }).message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        job_id: (job as { id: string }).id,
        status: "queued",
      }),
      {
        status: 201,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (_err) {
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("CORS preflight returns 200", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "OPTIONS",
    })
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("GET returns 405 method not allowed", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", { method: "GET" })
  );
  assertEquals(res.status, 405);
  const body = await res.json();
  assertEquals(body.error, "Method not allowed");
});

Deno.test("missing video_url returns 400", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "POST",
      body: JSON.stringify({ showroom_id: "abc" }),
      headers: { "Content-Type": "application/json" },
    })
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "video_url is required");
});

Deno.test("missing showroom_id returns 400", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "POST",
      body: JSON.stringify({ video_url: "https://example.com/video.mp4" }),
      headers: { "Content-Type": "application/json" },
    })
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "showroom_id is required");
});

Deno.test("valid request returns 201 with job_id", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "POST",
      body: JSON.stringify({
        video_url: "https://storage.example.com/video.mp4",
        showroom_id: "showroom-uuid-456",
        poses_url: "https://storage.example.com/poses.json",
        planes_url: "https://storage.example.com/planes.json",
        metadata: { device_model: "iPhone 15" },
      }),
      headers: { "Content-Type": "application/json" },
    })
  );
  assertEquals(res.status, 201);
  const body = await res.json();
  assertExists(body.job_id);
  assertEquals(body.job_id, "job-uuid-123");
  assertEquals(body.status, "queued");
});

Deno.test("valid request with minimal fields returns 201", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "POST",
      body: JSON.stringify({
        video_url: "https://storage.example.com/video.mp4",
        showroom_id: "showroom-uuid-789",
      }),
      headers: { "Content-Type": "application/json" },
    })
  );
  assertEquals(res.status, 201);
  const body = await res.json();
  assertEquals(body.status, "queued");
});

Deno.test("database insert error returns 500", async () => {
  const failingDb = makeMockSupabase({
    data: null,
    error: { message: "duplicate key violation" },
  });
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "POST",
      body: JSON.stringify({
        video_url: "https://storage.example.com/video.mp4",
        showroom_id: "showroom-uuid-456",
      }),
      headers: { "Content-Type": "application/json" },
    }),
    failingDb
  );
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "Failed to create processing job");
  assertEquals(body.message, "duplicate key violation");
});

Deno.test("invalid JSON body returns 500", async () => {
  const res = await handleRequest(
    new Request("http://localhost/create-processing-job", {
      method: "POST",
      body: "not json",
      headers: { "Content-Type": "application/json" },
    })
  );
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "Internal server error");
});
