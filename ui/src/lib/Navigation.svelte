<!-- src/lib/Navigation.svelte -->
<script lang="ts">
  export let data
  import { getDrawerStore } from "@skeletonlabs/skeleton";
  import { page } from '$app/stores';

  const drawerStore = getDrawerStore();

  function drawerClose(): void {
    drawerStore.close();
  }

  // TODO: Use {$page.url.pathname === '/'} to show the currenctly active navigation page.
</script>


<nav class="list-nav p-4">
	<ul>
		<li><a href="/" on:click={drawerClose}>Home</a></li>
		<li><a href="/auth" on:click={drawerClose}>Auth</a></li>
		<!-- {#if data.session} -->
		<li><a href="/profile" on:click={drawerClose}>Profile</a></li>
		<!-- {/if} -->
	</ul>
</nav>