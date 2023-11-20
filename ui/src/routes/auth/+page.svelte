<!-- // src/routes/auth/+page.svelte -->
<script>
  export let data
  let { supabase } = data
  $: ({ supabase } = data)

  let email
  let password

  const handleSignIn = async () => {
    await supabase.auth.signInWithPassword({
      email,
      password,
    })
  }

  const handleSignOut = async () => {
    await supabase.auth.signOut()
  }
</script>

<p>Go to the <a href="/">frontpage</a></p>
{#if data.session}
<button on:click="{handleSignOut}">Sign out</button>
{:else}
<form on:submit="{handleSignIn}">
  <input name="email" bind:value="{email}" />
  <input type="password" name="password" bind:value="{password}" />
  <button>Sign in</button>
</form>
{/if}

