<!-- // src/routes/auth/+page.svelte -->
<script>
  import { PasswordInput, TextInput, Button } from "carbon-components-svelte";

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
<Button on:click="{handleSignOut}">Sign out</Button>
{:else}
<form on:submit|preventDefault="{handleSignIn}">
  <TextInput
    name="email"
    labelText="Email"
    placeholder="Enter email..."
    bind:value="{email}"
  />
  <PasswordInput
    name="password"
    labelText="Password"
    placeholder="Enter password..."
    bind:value="{password}"
  />
  <Button type="submit">Sign in</Button>
</form>
{/if}
