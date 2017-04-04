export const getModel = model => Object.entries(model.properties)
  .reduce(
    (acc, [, v]) => ({ ...acc, [v.name]: v.value === '' ? null : v.value === null ? undefined : v.value }),
    { dataAccess: model.dataAccess },
)

export const updateProperties = (model, properties) => properties.map(
  p =>
    model[p.name] === undefined
      ? p
      : { ...p, value: model[p.name] },
)
