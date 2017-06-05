import { number, object, string, array } from 'yup'

import { formatDateTime } from 'helpers/dateHelper'

const defaultDate = formatDateTime(new Date())
const sureString = string().ensure().default('')
const sureDateString = string().default(defaultDate)
const positiveNum = number().positive()
const positiveNumArray = array(positiveNum).min(1).default([])

const base = {
  name: sureString
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),

  dataSource: sureString,
  shortName: sureString,
  addressId: sureString,
  liqReason: sureString,
  liqDate: sureString,
  registrationReason: sureString,
  contactPerson: sureString,
  classified: sureString,
  foreignParticipation: sureString,
  reorgTypeCode: sureString,
  suspensionEnd: sureString,
  suspensionStart: sureString,
  telephoneNo: sureString,
  emailAddress: string().email('IsNotEmail'),
  webAddress: sureString,
  reorgReferences: sureString,
  notes: sureString,
  employeesDate: sureDateString,
  employeesYear: sureDateString,
  externalIdDate: sureDateString,
  statIdDate: sureDateString,
  statusDate: sureDateString,
  taxRegDate: sureDateString,
  turnoveDate: sureDateString,
  turnoverYear: sureDateString,
  statId: sureString.required('StatIdIsRequired'),
  taxRegId: positiveNum,
  regMainActivityId: positiveNum,
  externalId: positiveNum,
  externalIdType: positiveNum,
  postalAddressId: positiveNum,
  numOfPeople: positiveNum.default(0),
  employees: positiveNum.default(0),
  turnover: positiveNum.default(0),
}

const localUnit = {
  legalUnitIdDate: sureDateString,

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
  actualMainActivity1: sureString,
  actualMainActivity2: sureString,
  actualMainActivityDate: sureString,

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
  actualMainActivity1: sureString,
  actualMainActivity2: sureString,
  actualMainActivityDate: sureString,
  entGroupRole: sureString,
  legalUnits: positiveNumArray.required('LegalUnitIsRequired'),
  localUnits: positiveNumArray.required('LocalUnitIsRequired'),

  entGroupId: positiveNum,
  enterpriseUnitRegId: positiveNum,
}

const enterpriseGroup = {
  statId: positiveNum,
  statIdDate: sureDateString,
  taxRegId: positiveNum,
  taxRegDate: sureDateString,
  externalId: positiveNum,
  externalIdType: positiveNum,
  externalIdDate: sureDateString,
  dataSource: sureString,
  name: sureString
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),
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
  reorgDate: sureDateString,
  reorgReferences: sureString,
  contactPerson: sureString,
  employees: positiveNum.default(0),
  employeesFte: number(),
  employeesYear: sureDateString,
  employeesDate: sureDateString,
  turnover: number(),
  turnoverYear: sureDateString,
  turnoveDate: sureDateString,
  status: sureString,
  statusDate: sureDateString,
  notes: sureString,
  enterpriseUnits: positiveNumArray.required('EnterpriseUnitIsRequired'),
  legalUnits: positiveNumArray.required('LegalUnitIsRequired'),
  postalAddressId: positiveNum,
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
