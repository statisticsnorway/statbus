<!-- // src/routes/+page.svelte -->
<script lang="ts">
  export let data;

  // Accessing the Supabase URL environment variable
  const supabaseUrl = import.meta.env.VITE_PUBLIC_SUPABASE_URL;

  let activity_categories = [];
  async function loadData() {
    const { data: result } = await data.supabase.from('activity_category').select('*').limit(20);
    activity_categories = result;
  }

  $: if (data.session) {
    loadData();
  }
</script>

{#if data.session}
  <p>Currently logged in.<a href="/auth">Go to Auth Page to logout</a></p>
  <p>See your <a href="/profile">profile</a></p>
{:else}
  <p>Not logged in.</p>
  <a href="/auth">Login</a> <!-- Link to the Auth Page -->
{/if}

<h1>Welcome to StatBus</h1>
<p>The Backend is hosted at <a target="_blank" href="{supabaseUrl}">{supabaseUrl}</a></p>
<p>Visit <a target="_blank" href="https://kit.svelte.dev">kit.svelte.dev</a> to read the frontend framework documentation</p>


{#if data.session}
  <p>client-side data fetching with RLS:</p>
  <pre>{JSON.stringify(activity_categories, null, 2)}</pre>
  <a href="/auth">Go to Auth Page</a> <!-- Link to the Auth Page -->
{:else}
  <p>Not logged in.</p>
  <a href="/auth">Login</a> <!-- Link to the Auth Page -->
{/if}
