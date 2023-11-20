<!-- src/routes/profile/+page.svelte -->
<script lang="ts">
  export let data

  let { user, activity_categories } = data
  $: ({ user, activity_categories } = data)
</script>
<p>Go to the <a href="/">frontpage</a></p>

<h1>Profile for {user.email}</h1>

<h2>User Information</h2>
<pre>{JSON.stringify(user, null, 2)}</pre>

<h2>Activity Categories</h2>
<pre>{JSON.stringify(activity_categories, null, 2)}</pre>
