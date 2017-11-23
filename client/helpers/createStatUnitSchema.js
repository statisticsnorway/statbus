import { number, object, string, array } from 'yup'
import { pipe } from 'ramda'

import { getMandatoryFields } from 'helpers/config'
import { formatDateTime } from 'helpers/dateHelper'
import { statUnitTypes } from 'helpers/enums'
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
const requiredPositiveNumber = number()
  .positive()
  .default(0)
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
  foreignParticipationCountryId: positiveNum,
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
  taxRegId: positiveNum,
  regMainActivityId: positiveNum,
  externalId: positiveNum,
  externalIdType: positiveNum,
  postalAddressId: requiredPositiveNumber,
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
  [statUnitTypes.get(1)]: {
    legalUnitIdDate: nullableDate,
    legalUnitId: positiveNum,
    registrationDate: sureDateString,
    activities: activitiesArray,
  },

  // Legal Unit
  [statUnitTypes.get(2)]: {
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
  [statUnitTypes.get(3)]: {
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
  [statUnitTypes.get(4)]: {
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
    postalAddressId: requiredPositiveNumber,
    size: positiveNum,
    dataSourceClassificationId: positiveNum,
    reorgTypeId: positiveNum,
    unitStatusId: positiveNum,
  },
}

const configureSchema = (typeId, permissions) => {
  const type = statUnitTypes.get(typeId)
  const mandatoryFields = getMandatoryFields(type)
  const updateRule = (name, rule) =>
    mandatoryFields.includes(name) ? rule.required(`${name}IsRequired`) : rule

  return Object.entries({
    ...base,
    ...byType[type],
  }).reduce(
    (acc, [prop, rule]) =>
      permissions.some(x => x.propertyName === toPascalCase(prop) && (x.canRead || x.canWrite))
        ? {
          ...acc,
          [prop]: updateRule(toPascalCase(prop), rule),
        }
        : { ...acc },
    {},
  )
}

export default pipe(configureSchema, object)
