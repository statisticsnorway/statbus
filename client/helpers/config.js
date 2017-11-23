import { statUnitTypes, roles } from './enums'

// eslint-disable-next-line no-underscore-dangle
const config = window.__initialStateFromServer

const checkDAAByType = (target, type) =>
  config.dataAccessAttributes.findIndex(attr => `${statUnitTypes.get(type)}.${target}`.toLowerCase() === attr.toLowerCase())

export const checkDataAccessAttribute = target =>
  checkDAAByType(target, 1) >= 0 &&
  checkDAAByType(target, 2) >= 0 &&
  checkDAAByType(target, 3) >= 0 &&
  checkDAAByType(target, 4) >= 0

export const checkSystemFunction = target => config.systemFunctions.includes(target)

export const getMandatoryFields = unitType =>
  Object.entries({
    ...config.mandatoryFields.StatUnit,
    ...config.mandatoryFields[statUnitTypes.get(Number(unitType))],
  }).reduce((result, [prop, isRequired]) => {
    if (isRequired) result.push(prop)
    return result
  }, [])

export const isInRole = (...userRoles) => config.roles.some(r => userRoles.some(x => x === r))

export const isAdmin = () => isInRole(roles.admin)

export default config
