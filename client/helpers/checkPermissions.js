/* eslint-disable no-underscore-dangle */
import statUnitTypes from './statUnitTypes'

const dAAs = window.__initialStateFromServer.dataAccessAttributes
const sFs = window.__initialStateFromServer.systemFunctions

export const dataAccessAttribute = target =>
  dAAs.findIndex(item => (`${statUnitTypes.get(1)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0 &&
  dAAs.findIndex(item => (`${statUnitTypes.get(2)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0 &&
  dAAs.findIndex(item => (`${statUnitTypes.get(3)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0 &&
  dAAs.findIndex(item => (`${statUnitTypes.get(4)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0

export const systemFunction = target => sFs.includes(target)
