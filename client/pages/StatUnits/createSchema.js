import { number, object, string, array } from 'yup'

import { formatDateTime } from 'helpers/dateHelper'

const defaultDate = formatDateTime(new Date())
const sureString = string().ensure().default(undefined)
const sureDateString = string().default(defaultDate)
const nullableDate = string().ensure().default(undefined)
const positiveNum = number().positive().nullable(true).default(undefined)
const requiredPositiveNumber = number().positive().default(0)
const positiveNumArray = array(positiveNum).min(1).default([])
const year = number()
              .positive()
              .min(1900)
              .max(new Date().getFullYear())
              .nullable(true)

const base = {
  name: sureString
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),

  dataSource: sureString.required('DataSourceIsRequired'),
  shortName: sureString.required('ShortNameIsRequired'),
  addressId: requiredPositiveNumber.required('AddressIdIsRequired'),
  liqReason: sureString,
  liqDate: sureString,
  registrationReason: sureString,
  contactPerson: sureString.required('ContactPersonIsRequired'),
  classified: sureString,
  foreignParticipation: sureString,
  countryId: positiveNum,
  reorgTypeCode: sureString,
  suspensionEnd: sureString,
  suspensionStart: sureString,
  telephoneNo: sureString,
  emailAddress: string().email('IsNotEmail'),
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
  statId: sureString.required('StatIdIsRequired'),
  taxRegId: positiveNum,
  regMainActivityId: positiveNum,
  externalId: positiveNum,
  externalIdType: positiveNum,
  postalAddressId: requiredPositiveNumber.required('PostalAddressIdIsRequired'),
  numOfPeopleEmp: positiveNum,
  employees: positiveNum,
  turnover: positiveNum,
  parentOrgLinkId: positiveNum,
}

const localUnit = {
  legalUnitIdDate: nullableDate,

  legalUnitId: positiveNum,
  enterpriseUnitRegId: positiveNum,
  registrationDate: sureDateString,
}

const legalUnit = {
  entRegIdDate: sureDateString,
  founders: sureString,
  owner: sureString,
  legalFormId: positiveNum,
  instSectorCodeId: positiveNum,
  totalCapital: sureString,
  munCapitalShare: sureString,
  stateCapitalShare: sureString,
  privCapitalShare: sureString,
  foreignCapitalShare: sureString,
  foreignCapitalCurrency: sureString,

  enterpriseUnitRegId: positiveNum,
  enterpriseRegId: positiveNum,
  enterpriseGroupRegId: positiveNum,
  localUnits: positiveNumArray.required('LocalUnitIsRequired'),
}

const enterpriseUnit = {
  entGroupIdDate: sureDateString,
  instSectorCodeId: positiveNum,
  totalCapital: sureString,
  munCapitalShare: sureString,
  stateCapitalShare: sureString,
  privCapitalShare: sureString,
  foreignCapitalShare: sureString,
  foreignCapitalCurrency: sureString,
  entGroupRole: sureString,
  legalUnits: positiveNumArray.required('LegalUnitIsRequired'),
  localUnits: positiveNumArray.required('LocalUnitIsRequired'),

  entGroupId: positiveNum,
  enterpriseUnitRegId: positiveNum,
}

const enterpriseGroup = {
  statId: sureString.required('StatIdIsRequired'),
  statIdDate: nullableDate,
  taxRegId: positiveNum,
  taxRegDate: nullableDate,
  externalId: positiveNum,
  externalIdType: positiveNum,
  externalIdDate: nullableDate,
  dataSource: sureString.required('DataSourceIsRequired'),
  name: sureString
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),
  shortName: sureString.required('ShortNameIsRequired'),
  telephoneNo: sureString,
  emailAddress: sureString,
  wbAddress: sureString,
  entGroupType: sureString.required('EntGroupTypeIsRequired'),
  registrationDate: sureDateString,
  registrationReason: sureString,
  liqReason: sureString,
  suspensionStart: sureString,
  suspensionEnd: sureString,
  reorgTypeCode: sureString,
  reorgDate: nullableDate,
  reorgReferences: sureString,
  contactPerson: sureString.required('ContactPersonIsRequired'),
  employees: positiveNum,
  numOfPeopleEmp: positiveNum,
  employeesYear: year,
  employeesDate: nullableDate,
  turnover: positiveNum,
  turnoverYear: year,
  turnoverDate: nullableDate,
  status: sureString.required('StatusIsRequired'),
  statusDate: nullableDate.required('StatusDateIsRequired'),
  notes: sureString,
  enterpriseUnits: positiveNumArray.required('EnterpriseUnitIsRequired'),
  legalUnits: positiveNumArray.required('LegalUnitIsRequired'),
  postalAddressId: requiredPositiveNumber.required('PostalAddressIdIsRequired'),
}

const types = new Map([
  [1, localUnit],
  [2, legalUnit],
  [3, enterpriseUnit],
  [4, enterpriseGroup],
])

export default statUnitType => object({
  ...base,
  ...(types.get(Number(statUnitType)) || {}),
})
