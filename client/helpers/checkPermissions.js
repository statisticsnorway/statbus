/* eslint-disable no-underscore-dangle */
const dAAs = window.__initialStateFromServer.dataAccessAttributes
const sFs = window.__initialStateFromServer.systemFunctions

export const dataAccessAttribute = target => dAAs.includes(target)
export const systemFunction = target => sFs.includes(target)
