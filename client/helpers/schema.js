const getInnerErrors = ({ inner }) =>
  inner.reduce(
    (acc, cur) => ({ ...acc, [cur.path]: cur.errors }),
    {},
  )

export default getInnerErrors
