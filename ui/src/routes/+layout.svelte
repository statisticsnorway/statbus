<!-- src/routes/+layout.svelte -->
<script lang="ts">
  import "carbon-components-svelte/css/all.css";
  import { invalidate } from '$app/navigation'
  import { onMount } from 'svelte'
  import { Theme } from "carbon-components-svelte";
  import { themeStore } from '../stores'; // import the store

  export let data

  let { supabase, session } = data
  $: ({ supabase, session } = data)

  onMount(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, _session) => {
      if (_session?.expires_at !== session?.expires_at) {
        invalidate('supabase:auth')
      }
    })

    return () => subscription.unsubscribe()
  });

</script>

<Theme bind:theme={$themeStore} persist persistKey="__carbon-theme"
  tokens={{
    // Colors from legacy.statbus.oreg login button.
    "interactive-01": "#2185d0",
    "hover-primary": "#0d71bb",
    //"active-primary": "#9f1853",
  }}
/>

<slot />