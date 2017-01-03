/* eslint-disable no-underscore-dangle */
const dAAs = window.__initialStateFromServer.dataAccessAttributes
const sFs = window.__initialStateFromServer.systemFunctions

export const dataAccessAttribute = target => dAAs
                        .findIndex(item => target.toLowerCase() === item.toLowerCase()) >= 0
export const systemFunction = target => sFs.includes(target)
