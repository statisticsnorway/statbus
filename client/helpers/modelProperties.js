export const createModel = ({ dataAccess, properties }) => Object.entries(properties)
  .reduce(
    (acc, [, v]) => ({
      ...acc,
      [v.name]: v.value === ''
        ? null
        : v.value === null
          ? undefined
          : v.value,
    }),
    { dataAccess },
  )

export const updateProperties = (model, properties) => properties.map(
  p => model[p.name] === undefined
    ? p
    : { ...p, value: model[p.name] },
)
