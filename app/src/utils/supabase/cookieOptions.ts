// The supabase client names the cookie after the hostname,
// and Statbus does web requests from the web, and from the app
// inside a docker container, to the kong host.
// To prevent a mismatch we specifically name the cookie after the
// code of the deployment slot, so that the same cookie is used
// both in the browser and in the app backend.
export const cookieOptions = {
  name: `statbus-${process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE}`
};
