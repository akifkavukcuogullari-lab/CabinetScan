/**
 * Tests for get-job-results Edge Function.
 * Phase 3.4-test: Server Pipeline V2
 *
 * Run: deno test --allow-env supabase/functions/get-job-results/index.test.ts
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const completedJob = {
  id: "job-uuid-done",
  status: "completed",
  measurements_data: {
    room_name: "Kitchen",
    total_linear_ft: 18.5,
    wall_count: 3,
  },
  floor_plan_png_url: "https://storage.example.com/floor_plan.png",
  validation_passed: true,
  validation_issues: [],
  processing_time_ms: 45000,
  scale_confidence: "high",
  pipeline_version: "v2",
  stage_timings: {
    frame_extraction: 2000,
    depth_estimation: 15000,
    wall_detection: 3000,
  },
};

function makeMockSupabase(
  selectResult: { data: unknown; error: unknown } = {
    data: completedJob,
    error: null,
  }
) {
  return {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        eq: (_col: string, _val: string) => ({
          single: () => Promise.resolve(selectResult),
        }),
      }),
    }),
  };
}

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
    const url = new URL(req.url);
    const jobId = url.searchParams.get("job_id");

    if (!jobId) {
      return new Response(
        JSON.stringify({ error: "job_id query parameter is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { data: job, error } = await supabaseAdmin
      .from("processing_jobs")
      .select(
        `id, status, measurements_data, floor_plan_png_url,
        validation_passed, validation_issues, processing_time_ms,
        scale_confidence, pipeline_version, stage_timings`
      )
      .eq("id", jobId)
      .single();

    if (error || !job) {
      return new Response(
        JSON.stringify({ error: "Job not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const typedJob = job as {
      id: string;
      status: string;
      measurements_data: Record<string, unknown>;
      floor_plan_png_url: string | null;
      validation_passed: boolean;
      validation_issues: string[];
      processing_time_ms: number;
      scale_confidence: string | null;
      pipeline_version: string | null;
      stage_timings: Record<string, number>;
    };

    if (typedJob.status !== "completed") {
      return new Response(
        JSON.stringify({
          error: "Job is not completed",
          status: typedJob.status,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        job_id: typedJob.id,
        measurements_data: typedJob.measurements_data,
        floor_plan_png_url: typedJob.floor_plan_png_url,
        validation_passed: typedJob.validation_passed,
        validation_issues: typedJob.validation_issues || [],
        processing_time_ms: typedJob.processing_time_ms,
        scale_confidence: typedJob.scale_confidence,
        pipeline_version: typedJob.pipeline_version,
        stage_timings: typedJob.stage_timings,
      }),
      {
        status: 200,
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
    new Request("http://localhost/get-job-results", { method: "OPTIONS" })
  );
  assertEquals(res.status, 200);
});

Deno.test("missing job_id returns 400", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-results", { method: "GET" })
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "job_id query parameter is required");
});

Deno.test("nonexistent job returns 404", async () => {
  const emptyDb = makeMockSupabase({
    data: null,
    error: { message: "not found" },
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=bad-id", {
      method: "GET",
    }),
    emptyDb
  );
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.error, "Job not found");
});

Deno.test("non-completed job returns 400", async () => {
  const processingDb = makeMockSupabase({
    data: { ...completedJob, status: "processing" },
    error: null,
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-processing", {
      method: "GET",
    }),
    processingDb
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "Job is not completed");
  assertEquals(body.status, "processing");
});

Deno.test("queued job returns 400", async () => {
  const queuedDb = makeMockSupabase({
    data: { ...completedJob, status: "queued" },
    error: null,
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-queued", {
      method: "GET",
    }),
    queuedDb
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "Job is not completed");
});

Deno.test("failed job returns 400", async () => {
  const failedDb = makeMockSupabase({
    data: { ...completedJob, status: "failed" },
    error: null,
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-failed", {
      method: "GET",
    }),
    failedDb
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "Job is not completed");
});

Deno.test("completed job returns measurements_data", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-uuid-done", {
      method: "GET",
    })
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.job_id, "job-uuid-done");
  assertExists(body.measurements_data);
  assertEquals(body.measurements_data.room_name, "Kitchen");
  assertEquals(body.measurements_data.total_linear_ft, 18.5);
  assertEquals(body.measurements_data.wall_count, 3);
});

Deno.test("completed job returns floor plan URL", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-uuid-done", {
      method: "GET",
    })
  );
  const body = await res.json();
  assertEquals(
    body.floor_plan_png_url,
    "https://storage.example.com/floor_plan.png"
  );
});

Deno.test("completed job returns validation info", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-uuid-done", {
      method: "GET",
    })
  );
  const body = await res.json();
  assertEquals(body.validation_passed, true);
  assertEquals(body.validation_issues, []);
});

Deno.test("completed job returns pipeline metadata", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-uuid-done", {
      method: "GET",
    })
  );
  const body = await res.json();
  assertEquals(body.processing_time_ms, 45000);
  assertEquals(body.scale_confidence, "high");
  assertEquals(body.pipeline_version, "v2");
  assertExists(body.stage_timings);
});

Deno.test("response has all expected fields", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-uuid-done", {
      method: "GET",
    })
  );
  const body = await res.json();
  const expectedKeys = [
    "job_id",
    "measurements_data",
    "floor_plan_png_url",
    "validation_passed",
    "validation_issues",
    "processing_time_ms",
    "scale_confidence",
    "pipeline_version",
    "stage_timings",
  ];
  for (const key of expectedKeys) {
    assertEquals(key in body, true, `Missing key: ${key}`);
  }
});

Deno.test("validation issues passed through correctly", async () => {
  const jobWithIssues = {
    ...completedJob,
    validation_passed: false,
    validation_issues: ["Wall count mismatch", "Missing appliance"],
  };
  const db = makeMockSupabase({ data: jobWithIssues, error: null });
  const res = await handleRequest(
    new Request("http://localhost/get-job-results?job_id=job-issues", {
      method: "GET",
    }),
    db
  );
  const body = await res.json();
  assertEquals(body.validation_passed, false);
  assertEquals(body.validation_issues.length, 2);
  assertEquals(body.validation_issues[0], "Wall count mismatch");
});
