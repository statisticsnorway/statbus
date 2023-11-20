<!-- src/routes/+layout.svelte -->
<script lang="ts">
  import "../app.pcss";
  import { invalidate } from '$app/navigation'
  import { onMount } from 'svelte'
  import { themeStore } from '../stores'; // import the store
  import {
    AppShell,
    AppBar,
    Avatar,
    initializeStores,
    Drawer,
    getDrawerStore
  } from '@skeletonlabs/skeleton';
  import Navigation from '$lib/Navigation.svelte';

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

  let initials = session ? session.user.email : "";

  // State for hamburger menu drawer.
  initializeStores();
  const drawerStore = getDrawerStore();
  function drawerOpen(): void {
    drawerStore.open({});
  }
</script>

<Drawer>
  <h2 class="p-4">Navigation</h2>
  <hr />
  <Navigation />
</Drawer>

<AppShell slotSidebarLeft="bg-surface-500/5 w-0 lg:w-64">
  <svelte:fragment slot="header">
    <AppBar gridColumns="grid-cols-3" slotDefault="place-self-center" slotTrail="place-content-end">
      <svelte:fragment slot="lead">
        <div class="flex items-center">
            <button on:click={drawerOpen} class="lg:hidden btn btn-sm mr-4">
                <span>
                    <svg viewBox="0 0 100 80" class="fill-token w-4 h-4">
                        <rect width="100" height="20" />
                        <rect y="30" width="100" height="20" />
                        <rect y="60" width="100" height="20" />
                    </svg>
                </span>
            </button>
        </div>
      </svelte:fragment>
      <strong class="text-xl uppercase">
        <a href="/">StatBus</a>
      </strong>
      <svelte:fragment slot="trail">
        {#if session }
          <a href="/profile"><Avatar initials={initials} /></a>
        {/if}
      </svelte:fragment>
    </AppBar>
  </svelte:fragment>
  <svelte:fragment slot="sidebarLeft">
    <Navigation />
  </svelte:fragment>
  <!-- (sidebarRight) -->
  <!-- (pageHeader) -->
  <!-- Router Slot -->
  <slot />
  <!-- ---- / ---- -->
  <!-- (pageFooter) -->
  <!-- (footer) -->
</AppShell>
