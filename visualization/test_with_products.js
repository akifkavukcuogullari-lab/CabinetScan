/**
 * Test visualization with actual product reference images
 *
 * Kitchen Photo: https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/visualization_1764994833_22E51816.jpg
 *
 * Products:
 * - Cabinet: Warm honey/amber wood tone
 * - Countertop: White Calacatta marble with gray veining
 * - Backsplash: White herringbone pattern tile
 */

const FAL_API_KEY = "75a7a308-5810-4e9d-91a6-7eba36de83a5:f9c93ec0539a9da27cd881c0781bcfc7";

const KITCHEN_PHOTO_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/visualization_1764994833_22E51816.jpg";

// Pre-generated masks from earlier test
const MASKS = {
  cabinets: 'https://fal.media/files/elephant/XDbd3WOCL6QuYIHRhrZo__f2a582efe59e4081a8ce91588b371af3.png',
  countertop: 'https://fal.media/files/zebra/lmAg2UVd051lgJpUTgH-I_847913dbd16f49c1aba999f5ff3566de.png',
  backsplash: 'https://fal.media/files/zebra/aDalWb6GQCdXYgQcHfRdL_7e8969c3cf5244389bf93f4dab14a94a.png'
};

// Product descriptions based on the images provided
const PRODUCTS = {
  cabinet: {
    name: "Honey Oak Shaker",
    style: "shaker",
    color: "warm honey amber oak wood tone, golden brown wood grain",
    material: "solid oak wood"
  },
  countertop: {
    name: "Calacatta White Marble",
    material: "natural marble",
    color: "white calacatta marble with elegant gray veining, luxurious stone pattern",
    finish: "polished"
  },
  backsplash: {
    name: "White Herringbone Tile",
    material: "ceramic tile",
    color: "crisp white",
    pattern: "herringbone"
  }
};

const ENDPOINTS = {
  evfSam: 'https://queue.fal.run/fal-ai/evf-sam',
  fluxFill: 'https://queue.fal.run/fal-ai/flux-pro/v1/fill'
};

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function falApiCall(endpoint, payload, operationName) {
  console.log(`\n📍 ${operationName}: Starting...`);

  const submitResponse = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Authorization': `Key ${FAL_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });

  if (!submitResponse.ok) {
    const errorText = await submitResponse.text();
    throw new Error(`API error ${submitResponse.status}: ${errorText}`);
  }

  const submission = await submitResponse.json();

  if (submission.images || submission.image) {
    console.log(`✅ ${operationName}: Complete (immediate)`);
    return submission;
  }

  const statusUrl = submission.status_url;
  const resultUrl = submission.response_url;

  console.log(`   Polling for result...`);

  const maxPolls = 90;
  const pollInterval = 2000;

  for (let poll = 0; poll < maxPolls; poll++) {
    await sleep(pollInterval);

    const statusResponse = await fetch(statusUrl, {
      headers: { 'Authorization': `Key ${FAL_API_KEY}` }
    });

    const statusText = await statusResponse.text();
    let status;
    try {
      status = JSON.parse(statusText);
    } catch (e) {
      continue;
    }

    if (status.status === 'COMPLETED') {
      const resultResponse = await fetch(resultUrl, {
        headers: { 'Authorization': `Key ${FAL_API_KEY}` }
      });
      const result = await resultResponse.json();
      console.log(`✅ ${operationName}: Complete`);
      return result;
    }

    if (status.status === 'FAILED') {
      throw new Error(status.error || 'Processing failed');
    }

    if (poll % 5 === 0 && poll > 0) {
      console.log(`   Still processing... (${poll * 2}s)`);
    }
  }

  throw new Error('Timeout waiting for result');
}

async function runFullVisualization() {
  console.log('='.repeat(70));
  console.log('🎨 KITCHEN VISUALIZATION WITH PRODUCT REFERENCES');
  console.log('='.repeat(70));
  console.log('\nOriginal kitchen:', KITCHEN_PHOTO_URL);
  console.log('\nProducts to apply:');
  console.log(`  - Cabinet: ${PRODUCTS.cabinet.name} (${PRODUCTS.cabinet.color})`);
  console.log(`  - Countertop: ${PRODUCTS.countertop.name} (${PRODUCTS.countertop.color})`);
  console.log(`  - Backsplash: ${PRODUCTS.backsplash.name} (${PRODUCTS.backsplash.pattern})`);
  console.log('\nUsing pre-generated masks...');

  let currentImage = KITCHEN_PHOTO_URL;
  const steps = [];

  // Step 1: Inpaint Cabinets with honey oak wood
  console.log('\n' + '-'.repeat(50));
  console.log('STEP 1: Replacing cabinets with Honey Oak');
  console.log('-'.repeat(50));

  const cabinetPrompt = `${PRODUCTS.cabinet.color} ${PRODUCTS.cabinet.material} ${PRODUCTS.cabinet.style} style kitchen cabinets, beautiful cabinet doors with brushed nickel hardware, warm wood grain texture, high-end kitchen design, photorealistic, professional photography lighting, 8k resolution`;
  console.log(`Prompt: ${cabinetPrompt}`);

  const cabinetResult = await falApiCall(ENDPOINTS.fluxFill, {
    image_url: currentImage,
    mask_url: MASKS.cabinets,
    prompt: cabinetPrompt,
    num_images: 1,
    safety_tolerance: 2,
    output_format: 'jpeg'
  }, 'Cabinet Inpainting');

  currentImage = cabinetResult.images[0].url;
  steps.push({ element: 'cabinets', url: currentImage });
  console.log(`\n🎉 Cabinets done: ${currentImage}`);

  // Step 2: Inpaint Countertop with Calacatta marble
  console.log('\n' + '-'.repeat(50));
  console.log('STEP 2: Replacing countertop with Calacatta Marble');
  console.log('-'.repeat(50));

  const countertopPrompt = `${PRODUCTS.countertop.color} ${PRODUCTS.countertop.material} kitchen countertop, ${PRODUCTS.countertop.finish} finish, luxurious natural stone surface with elegant veining pattern, photorealistic material texture, natural lighting, 8k resolution`;
  console.log(`Prompt: ${countertopPrompt}`);

  const countertopResult = await falApiCall(ENDPOINTS.fluxFill, {
    image_url: currentImage,
    mask_url: MASKS.countertop,
    prompt: countertopPrompt,
    num_images: 1,
    safety_tolerance: 2,
    output_format: 'jpeg'
  }, 'Countertop Inpainting');

  currentImage = countertopResult.images[0].url;
  steps.push({ element: 'countertop', url: currentImage });
  console.log(`\n🎉 Countertop done: ${currentImage}`);

  // Step 3: Inpaint Backsplash with white herringbone
  console.log('\n' + '-'.repeat(50));
  console.log('STEP 3: Replacing backsplash with White Herringbone');
  console.log('-'.repeat(50));

  const backsplashPrompt = `${PRODUCTS.backsplash.color} ${PRODUCTS.backsplash.material} kitchen backsplash, ${PRODUCTS.backsplash.pattern} pattern, designer kitchen tile work with clean grout lines, professional installation, photorealistic, 8k resolution`;
  console.log(`Prompt: ${backsplashPrompt}`);

  const backsplashResult = await falApiCall(ENDPOINTS.fluxFill, {
    image_url: currentImage,
    mask_url: MASKS.backsplash,
    prompt: backsplashPrompt,
    num_images: 1,
    safety_tolerance: 2,
    output_format: 'jpeg'
  }, 'Backsplash Inpainting');

  currentImage = backsplashResult.images[0].url;
  steps.push({ element: 'backsplash', url: currentImage });
  console.log(`\n🎉 Backsplash done: ${currentImage}`);

  // Final summary
  console.log('\n' + '='.repeat(70));
  console.log('✅ VISUALIZATION COMPLETE!');
  console.log('='.repeat(70));
  console.log('\nOriginal kitchen:');
  console.log(`  ${KITCHEN_PHOTO_URL}`);
  console.log('\nStep-by-step results:');
  steps.forEach((step, i) => {
    console.log(`  ${i + 1}. After ${step.element}: ${step.url}`);
  });
  console.log('\n🎨 FINAL RESULT:');
  console.log(`  ${currentImage}`);
  console.log('\n' + '='.repeat(70));

  return currentImage;
}

runFullVisualization()
  .then(finalUrl => {
    console.log('\nDone! Open the final URL in your browser to see the result.');
  })
  .catch(error => {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  });
