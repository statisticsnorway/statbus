<!-- src/routes/profile/+page.svelte -->
<script lang="ts">
  import {
    RadioButtonGroup,
    RadioButton,
  } from "carbon-components-svelte";
  import { themeStore } from '../../stores';

  export let data

  let { user, activity_categories } = data
  $: ({ user, activity_categories } = data)
</script>
<p>Go to the <a href="/">frontpage</a></p>

<h1>Profile for {user.email}</h1>
<h2>Select your theme</h2>
<RadioButtonGroup legendText="Carbon theme" bind:selected={$themeStore}>
  {#each ["white", "g10", "g80", "g90", "g100"] as value}
    <RadioButton labelText={value} {value} />
  {/each}
</RadioButtonGroup>

<h2>User Information</h2>
<pre>{JSON.stringify(user, null, 2)}</pre>

<h2>Activity Categories</h2>
<pre>{JSON.stringify(activity_categories, null, 2)}</pre>
