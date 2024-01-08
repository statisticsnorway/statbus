export default data =>
  data.adminstrativeCenter === null || data.adminstrativeCenter === undefined
    ? data.name
    : `${data.adminstrativeCenter}, ${data.name}`
