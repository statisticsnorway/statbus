import { statUnitTypes } from './enums'

// eslint-disable-next-line no-underscore-dangle
const config = window.__initialStateFromServer

export const checkDataAccessAttribute = target =>
  config.dataAccessAttributes.findIndex(item => (`${statUnitTypes.get(1)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0 &&
  config.dataAccessAttributes.findIndex(item => (`${statUnitTypes.get(2)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0 &&
  config.dataAccessAttributes.findIndex(item => (`${statUnitTypes.get(3)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0 &&
  config.dataAccessAttributes.findIndex(item => (`${statUnitTypes.get(4)}.${target}`).toLowerCase() === item.toLowerCase()) >= 0

export const checkSystemFunction = target => config.systemFunctions.includes(target)

export const checkMandatoryField = unitType => field =>
  config.mandatoryFields[`${statUnitTypes.get(unitType)}`][field]

export default config
