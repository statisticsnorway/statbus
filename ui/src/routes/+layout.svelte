<!-- src/routes/+layout.svelte -->
<script lang="ts">
  import "../app.pcss";
  import { invalidate } from '$app/navigation'
  import { onMount } from 'svelte'
  import { themeStore } from '../stores'; // import the store
  import { AppShell, AppBar } from '@skeletonlabs/skeleton';

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

  // Scroll to top when navigating between pages.
  import type { AfterNavigate } from '@sveltejs/kit';
  import { afterNavigate } from '$app/navigation';

  afterNavigate((params: AfterNavigate) => {
      const isNewPage: boolean = params.from?.route.id !== params.to?.route.id;
      const elemPage = document.querySelector('#page');
      if (isNewPage && elemPage !== null) {
          elemPage.scrollTop = 0;
      }
  });

</script>


<AppShell>
  <svelte:fragment slot="header">
    <AppBar>AppBar</AppBar>
  </svelte:fragment>
  <!-- (sidebarLeft) -->
  <!-- (sidebarRight) -->
  <!-- (pageHeader) -->
  <!-- Router Slot -->
  <slot />
  <!-- ---- / ---- -->
  <!-- (pageFooter) -->
  <!-- (footer) -->
</AppShell>
