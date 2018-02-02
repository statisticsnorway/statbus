import { number, object, string, array } from 'yup'
import R from 'ramda'

import { getMandatoryFields } from 'helpers/config'
import { formatDateTime } from 'helpers/dateHelper'
import { toPascalCase } from 'helpers/string'

const defaultDate = formatDateTime(new Date())
const sureString = string()
  .ensure()
  .default(undefined)
const sureDateString = string().default(defaultDate)
const nullableDate = string()
  .ensure()
  .default(undefined)
const positiveNum = number()
  .positive()
  .nullable(true)
  .default(undefined)
const positiveNumArray = array(positiveNum)
  .min(1)
  .ensure()
  .default([])
const year = number()
  .positive()
  .min(1900)
  .max(new Date().getFullYear())
  .nullable(true)
const activitiesArray = array(object())
  .min(1)
  .default(undefined)
const personsArray = array(object())
  .min(1)
  .default(undefined)
const nullablePositiveNumArray = array(positiveNum)
  .min(0)
  .ensure()
  .default([])

const createAsyncTest = (url, { unitId, unitType }) => value =>
  fetch(`${url}?${unitId ? `unitId=${unitId}&` : ''}unitType=${unitType}&value=${value}`).then(r =>
    r.json())

const base = {
  name: sureString.min(2, 'min 2 symbols').max(100, 'max 100 symbols'),
  dataSource: sureString,
  shortName: sureString,
  address: object(),
  liqReason: sureString,
  liqDate: sureString,
  registrationReason: sureString,
  contactPerson: sureString,
  classified: sureString,
  foreignParticipation: sureString,
  foreignParticipationCountriesUnits: positiveNumArray,
  reorgTypeCode: sureString,
  suspensionEnd: sureString,
  suspensionStart: sureString,
  telephoneNo: sureString,
  emailAddress: sureString,
  webAddress: sureString,
  reorgReferences: sureString,
  reorgDate: nullableDate,
  notes: sureString,
  employeesDate: nullableDate,
  employeesYear: year,
  externalIdDate: nullableDate,
  statIdDate: nullableDate,
  statusDate: nullableDate,
  taxRegDate: nullableDate,
  turnoverDate: nullableDate,
  turnoverYear: year,
  statId: sureString,
  taxRegId: sureString,
  regMainActivityId: positiveNum,
  externalId: sureString,
  externalIdType: positiveNum,
  numOfPeopleEmp: positiveNum,
  employees: positiveNum,
  turnover: positiveNum,
  parentOrgLinkId: positiveNum,
  status: sureString,
  persons: personsArray,
  size: positiveNum,
  foreignParticipationId: positiveNum,
  dataSourceClassificationId: positiveNum,
  reorgTypeId: positiveNum,
  unitStatusId: positiveNum,
}

const byType = {
  // Local Unit
  1: {
    legalUnitIdDate: nullableDate,
    legalUnitId: positiveNum,
    registrationDate: sureDateString,
    activities: activitiesArray,
  },

  // Legal Unit
  2: {
    entRegIdDate: sureDateString,
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
  },

  // Enterprise Unit
  3: {
    entGroupIdDate: sureDateString,
    instSectorCodeId: positiveNum,
    totalCapital: sureString,
    munCapitalShare: sureString,
    stateCapitalShare: sureString,
    privCapitalShare: sureString,
    foreignCapitalShare: sureString,
    foreignCapitalCurrency: sureString,
    entGroupRole: sureString,
    legalUnits: positiveNumArray,
    entGroupId: positiveNum,
    enterpriseUnitRegId: positiveNum,
    activities: activitiesArray,
  },

  // Enterprise Group
  4: {
    statId: sureString,
    statIdDate: nullableDate,
    taxRegId: positiveNum,
    taxRegDate: nullableDate,
    externalId: positiveNum,
    externalIdType: positiveNum,
    externalIdDate: nullableDate,
    dataSource: sureString,
    name: sureString.min(2, 'min 2 symbols').max(100, 'max 100 symbols'),
    shortName: sureString,
    telephoneNo: sureString,
    emailAddress: sureString,
    wbAddress: sureString,
    entGroupType: sureString,
    registrationDate: sureDateString,
    registrationReason: sureString,
    liqReason: sureString,
    suspensionStart: sureString,
    suspensionEnd: sureString,
    reorgTypeCode: sureString,
    reorgDate: nullableDate,
    reorgReferences: sureString,
    contactPerson: sureString,
    employees: positiveNum,
    numOfPeopleEmp: positiveNum,
    employeesYear: year,
    employeesDate: nullableDate,
    turnover: positiveNum,
    turnoverYear: year,
    turnoverDate: nullableDate,
    statusDate: nullableDate,
    notes: sureString,
    enterpriseUnits: positiveNumArray,
    size: positiveNum,
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
        createAsyncTest(asyncTestFields.get(name), { unitId, unitType }),
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
