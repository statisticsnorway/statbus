export default region =>
  region.adminstrativeCenter === null || region.adminstrativeCenter === undefined
    ? region.name
    : `${region.adminstrativeCenter}, ${region.name}`
