<!-- // src/routes/auth/+page.svelte -->
<script lang="ts">
	export let data;
	let { supabase } = data;
	$: ({ supabase } = data);

	let email: string;
	let password: string;

	const handleSignIn = async () => {
		await supabase.auth.signInWithPassword({
			email,
			password
		});
	};

	const handleSignOut = async () => {
		await supabase.auth.signOut();
	};
</script>

<div class="container mx-auto p-4">
	{#if data.session}
		<button
			class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
			on:click={handleSignOut}>Sign out</button
		>
	{:else}
		<form on:submit|preventDefault={handleSignIn} class="space-y-4">
			<div>
				<label for="email" class="block text-gray-700 text-sm font-bold mb-2">Email</label>
				<input
					id="email"
					type="email"
					name="email"
					bind:value={email}
					class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
				/>
			</div>

			<div>
				<label for="password" class="block text-gray-700 text-sm font-bold mb-2">Password</label>
				<input
					id="password"
					type="password"
					name="password"
					bind:value={password}
					class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 mb-3 leading-tight focus:outline-none focus:shadow-outline"
				/>
			</div>

			<button
				type="submit"
				class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline"
				>Sign in</button
			>
		</form>
	{/if}
</div>
