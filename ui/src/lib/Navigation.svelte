<!-- src/lib/Navigation.svelte -->
<script lang="ts">
	import { page } from '$app/stores';
	import { getDrawerStore } from '@skeletonlabs/skeleton';
	import { getContext } from 'svelte';

	export let data;
	let { supabase, session } = data;

	const drawerStore = getDrawerStore();

	function drawerClose(): void {
		drawerStore.close();
	}

	$: activePage = $page.url.pathname;
</script>

<nav class="list-nav p-4">
	<ul>
		<li class:active={activePage === '/'}><a href="/" on:click={drawerClose}>Home</a></li>
		<li class:active={activePage === '/auth'}><a href="/auth" on:click={drawerClose}>Auth</a></li>
		{#if session}
			<li class:active={activePage === '/profile'}>
				<a href="/profile" on:click={drawerClose}>Profile</a>
			</li>
		{/if}
	</ul>
</nav>

<style>
	.active {
		font-weight: bold; /* Makes the text bold */
		color: #007bff; /* Changes the text color */
		border-bottom: 2px solid #007bff; /* Adds a bottom border */
	}
</style>
