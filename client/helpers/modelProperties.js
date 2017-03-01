export const getModel = properties => Object.entries(properties)
  .reduce(
    (acc, [, v]) => ({ ...acc, [v.name]: v.value === '' ? null : v.value }),
    {},
)

export const updateProperties = (model, properties) => properties.map(
  p =>
    model[p.name] === undefined
      ? p
      : { ...p, value: model[p.name] },
)
