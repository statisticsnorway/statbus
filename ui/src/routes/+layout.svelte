<!-- src/routes/+layout.svelte -->
<script lang="ts">
  import "../app.pcss";
  import { invalidate } from '$app/navigation'
  import { onMount } from 'svelte'
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

<slot></slot>