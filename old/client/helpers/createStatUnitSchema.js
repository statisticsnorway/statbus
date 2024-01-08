import { number, object, string, array, bool, mixed } from 'yup'
import * as R from 'ramda'

import config, { getMandatoryFields } from '/helpers/config'
import { getDate } from '/helpers/dateHelper'
import { toPascalCase } from '/helpers/string'

const { validationSettings } = config

const sureString = string()
  .ensure()
  .default(undefined)
const nullableDate = mixed().nullable(true)
const currentDate = mixed().default(getDate())
const positiveNum = number()
  .positive()
  .nullable(true)
  .default(undefined)
const positiveOrZeroNum = number()
  .min(0)
  .nullable(true)
  .default(undefined)
const positiveNumArray = array(positiveNum)
  .nullable(true)
  .ensure()
  .default([])
const activitiesArray = array(object()).default(undefined)
const personsArray = array(object()).default(undefined)
const nullablePositiveNumArray = array(positiveNum)
  .min(0)
  .ensure()
  .default([])

const statId = (name, isRequired) =>
  validationSettings.ValidateStatIdChecksum
    ? string().test({
      name,
      message: 'InvalidChecksum',
      test(value) {
        if (!value && isRequired) {
          return this.createError({
            path: name,
            message: 'StatIdIsRequired',
          })
        }

        if (value.length > 8) {
          return this.createError({
            path: name,
            message: 'ShouldNotBeGreaterThenEight',
          })
        }
        if (value.length <= 8) {
          const okpo = (Array(20).join('0') + value)
            .substr(-8)
            .split('')
            .map(x => Number(x))
          const okpoWithoutLast = R.dropLast(1, okpo)
          const checkNumber = R.last(okpo)
          // eslint-disable-next-line no-mixed-operators
          let sum = okpoWithoutLast.map((v, i) => ((i % 10) + 1) * v).reduce((a, b) => a + b, 0)
          let remainder = sum % 11

          if (remainder >= 10) {
            // eslint-disable-next-line no-mixed-operators
            sum = okpoWithoutLast.map((v, i) => ((i % 10) + 3) * v).reduce((a, b) => a + b, 0)
            remainder = sum % 11
          }

          if (!Number.isNaN(remainder) && (remainder === checkNumber || remainder === 10)) {
            return true
          }
        }
        return false
      },
    })
    : sureString

const createAsyncTest = (url, { unitId, unitType }) =>
  R.memoize(value =>
    fetch(`${url}?${unitId ? `unitId=${unitId}&` : ''}unitType=${unitType}&value=${value}`).then(r => r.json()))

const base = {
  name: sureString.min(2, 'min 2 symbols').max(300, 'max 300 symbols'),
  dataSource: sureString,
  shortName: sureString,
  address: object(),
  actualAddress: object(),
  postalAddress: object(),
  liqReason: sureString,
  liqDate: nullableDate,
  registrationReasonId: positiveNum,
  classified: bool()
    .nullable(true)
    .default(false),
  foreignParticipationCountriesUnits: positiveNumArray,
  reorgTypeCode: sureString,
  suspensionEnd: nullableDate,
  suspensionStart: nullableDate,
  telephoneNo: sureString,
  emailAddress: sureString,
  webAddress: sureString,
  reorgReferences: positiveOrZeroNum,
  reorgDate: nullableDate,
  notes: sureString,
  employeesDate: nullableDate,
  employeesYear: nullableDate,
  externalIdDate: nullableDate,
  statIdDate: currentDate,
  statusDate: currentDate,
  taxRegId: sureString,
  taxRegDate: nullableDate,
  turnoverDate: nullableDate,
  turnoverYear: nullableDate,
  statId: statId('statId', config.mandatoryFields.StatUnit.StatId),
  regMainActivityId: positiveNum,
  externalId: sureString,
  externalIdType: sureString,
  numOfPeopleEmp: positiveOrZeroNum,
  employees: positiveOrZeroNum,
  turnover: positiveOrZeroNum,
  parentOrgLink: positiveNum,
  status: sureString,
  persons: personsArray,
  size: positiveOrZeroNum,
  foreignParticipationId: positiveNum,
  dataSourceClassificationId: positiveNum,
  reorgTypeId: positiveNum,
  unitStatusId: positiveNum,
  freeEconZone: bool(),
  countries: nullablePositiveNumArray,
  activities: activitiesArray,
  registrationDate: nullableDate,
}

const byType = {
  // Local Unit
  1: {
    legalUnitIdDate: nullableDate,
    legalUnitId: positiveNum,
  },

  // Legal Unit
  2: {
    entRegIdDate: nullableDate,
    legalFormId: positiveNum,
    instSectorCodeId: positiveNum,
    totalCapital: sureString,
    munCapitalShare: sureString,
    stateCapitalShare: sureString,
    privCapitalShare: sureString,
    foreignCapitalShare: sureString,
    foreignCapitalCurrency: sureString,
    enterpriseUnitRegId: positiveNum,
    localUnits: nullablePositiveNumArray,
    market: bool(),
  },

  // Enterprise Unit
  3: {
    entGroupIdDate: nullableDate,
    instSectorCodeId: positiveNum,
    totalCapital: sureString,
    munCapitalShare: sureString,
    stateCapitalShare: sureString,
    privCapitalShare: sureString,
    foreignCapitalShare: sureString,
    foreignCapitalCurrency: sureString,
    entGroupRoleId: positiveNum,
    legalUnits: positiveNumArray,
    entGroupId: positiveNum,
    commercial: bool(),
  },

  // Enterprise Group
  4: {
    statId: statId('statId', config.mandatoryFields.EnterpriseGroup.StatId),
    statIdDate: currentDate,
    taxRegId: sureString,
    taxRegDate: nullableDate,
    externalId: positiveNum,
    externalIdType: sureString,
    externalIdDate: nullableDate,
    dataSource: sureString,
    name: sureString.min(2, 'min 2 symbols').max(100, 'max 100 symbols'),
    shortName: sureString,
    telephoneNo: sureString,
    emailAddress: sureString,
    wbAddress: sureString,
    entGroupType: sureString,
    registrationDate: nullableDate,
    registrationReasonId: positiveNum,
    liqReason: sureString,
    suspensionStart: sureString,
    suspensionEnd: sureString,
    reorgTypeCode: sureString,
    reorgDate: nullableDate,
    reorgReferences: sureString,
    contactPerson: sureString,
    employees: positiveOrZeroNum,
    numOfPeopleEmp: positiveOrZeroNum,
    employeesYear: nullableDate,
    employeesDate: nullableDate,
    turnover: positiveOrZeroNum,
    turnoverYear: nullableDate,
    turnoverDate: nullableDate,
    statusDate: currentDate,
    notes: sureString,
    enterpriseUnits: positiveNumArray,
    size: positiveOrZeroNum,
    dataSourceClassificationId: positiveNum,
    reorgTypeId: positiveNum,
    unitStatusId: positiveNum,
  },
}

const configureSchema = (unitType, permissions, properties, unitId) => {
  const canRead = prop =>
    permissions.some(x => x.propertyName.split(/[.](.+)/)[1] === prop && (x.canRead || x.canWrite))
  const mandatoryFields = getMandatoryFields(unitType)
  const asyncTestFields = new Map(properties.reduce((acc, { name, validationUrl: url }) => {
    if (url) acc.push([toPascalCase(name), url])
    return acc
  }, []))

  const setRequired = ([name, rule]) => [
    name,
    mandatoryFields.includes(name) ? rule.required(`${name}IsRequired`) : rule,
  ]

  const setAsyncTest = ([name, rule]) => [
    name,
    asyncTestFields.has(name)
      ? rule.test(
        name,
        `${name}AsyncTestFailed`,
        validationSettings.StatIdUnique
          ? createAsyncTest(asyncTestFields.get(name), { unitId, unitType })
          : () => true,
      )
      : rule,
  ]

  const updateRule = R.pipe(setRequired, setAsyncTest)

  return Object.entries({
    ...base,
    ...byType[unitType],
  }).reduce((acc, [key, rule]) => {
    const prop = toPascalCase(key)
    return canRead(prop)
      ? {
        ...acc,
        [key]: updateRule([prop, rule])[1],
      }
      : acc
  }, {})
}

export default R.pipe(configureSchema, object)
