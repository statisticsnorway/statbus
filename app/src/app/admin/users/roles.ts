export const userRoles = [
  { value: "admin_user", label: "Admin", description: "Can do everything" },
  {
    value: "regular_user",
    label: "Regular",
    description: "Can view and edit data, but not change setup",
  },
  // restricted_user not in use yet
  //   { value: "restricted_user", label: "Restricted" description: "Can only insert and edit data for selected regions or activity categories"},
  {
    value: "external_user",
    label: "External",
    description: "Can see everything but not make any edits",
  },
];
