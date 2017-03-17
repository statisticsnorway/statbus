import { number, object, string, date, array } from 'yup'
import { formatDateTime } from 'helpers/dateHelper'

const defaultDate = formatDateTime(new Date())
const baseSchema = {

  name: string()
    .ensure()
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),

  dataSource: string().ensure(),
  shortName: string().ensure(),
  addressId: string().ensure(),
  liqReason: string().ensure(),
  liqDate: string().ensure(),
  registrationReason: string().ensure(),
  contactPerson: string().ensure(),
  classified: string().ensure(),
  foreignParticipation: string().ensure(),
  reorgTypeCode: string().ensure(),
  suspensionEnd: string().ensure(),
  suspensionStart: string().ensure(),
  telephoneNo: string().ensure(),
  emailAddress: string().ensure(),
  webAddress: string().ensure(),
  reorgReferences: string().ensure(),
  notes: string().ensure(),
  employeesDate: date().default(defaultDate),
  employeesYear: date().default(defaultDate),
  externalIdDate: date().default(defaultDate),
  statIdDate: date().default(defaultDate),
  statusDate: date().default(defaultDate),
  taxRegDate: date().default(defaultDate),
  turnoveDate: date().default(defaultDate),
  turnoverYear: date().default(defaultDate),
}

const localUnit = {
  legalUnitIdDate: date().default(defaultDate),
}

const legalUnit = {
  entRegIdDate: date().default(defaultDate),
  founders: string().ensure(),
  owner: string().ensure(),
  legalForm: string().ensure(),
  instSectorCode: string().ensure(),
  totalCapital: string().ensure(),
  munCapitalShare: string().ensure(),
  stateCapitalShare: string().ensure(),
  privCapitalShare: string().ensure(),
  foreignCapitalShare: string().ensure(),
  foreignCapitalCurrency: string().ensure(),
  actualMainActivity1: string().ensure(),
  actualMainActivity2: string().ensure(),
  actualMainActivityDate: string().ensure(),
}

const enterpriseUnit = {
  entGroupIdDate: date().default(defaultDate),
  instSectorCode: string().ensure(),
  totalCapital: string().ensure(),
  munCapitalShare: string().ensure(),
  stateCapitalShare: string().ensure(),
  privCapitalShare: string().ensure(),
  foreignCapitalShare: string().ensure(),
  foreignCapitalCurrency: string().ensure(),
  actualMainActivity1: string().ensure(),
  actualMainActivity2: string().ensure(),
  actualMainActivityDate: string().ensure(),
  entGroupRole: string().ensure(),
  legalUnits: array().of(number().positive()).min(1).required('LegalUnitIsRequired'),
}

const enterpriseGroup = {
  statId: number().positive(),
  statIdDate: date().default(defaultDate),
  taxRegId: number().positive(),
  taxRegDate: date().default(defaultDate),
  externalId: number().positive(),
  externalIdType: number().positive(),
  externalIdDate: date().default(defaultDate),
  dataSource: string().ensure(),
  name: string()
    .ensure()
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),
  shortName: string().ensure(),
  telephoneNo: string().ensure(),
  emailAddress: string().ensure(),
  wbAddress: string().ensure(),
  entGroupType: string().ensure(),
  registrationDate: date().default(defaultDate),
  registrationReason: string().ensure(),
  liqReason: string().ensure(),
  suspensionStart: string().ensure(),
  suspensionEnd: string().ensure(),
  reorgTypeCode: string().ensure(),
  reorgDate: date().default(defaultDate),
  reorgReferences: string().ensure(),
  contactPerson: string().ensure(),
  employees: number().positive(),
  employeesFte: number(),
  employeesYear: date().default(defaultDate),
  employeesDate: date().default(defaultDate),
  turnover: number(),
  turnoverYear: date().default(defaultDate),
  turnoveDate: date().default(defaultDate),
  status: string().ensure(),
  statusDate: date().default(defaultDate),
  notes: string().ensure(),
  enterpriseUnits: array().of(number().positive()).min(1).required('EnterpriseUnitIsRequired'),
}

export const getSchema = (statUnitType) => {
  let statUnitSchema
  let temp
  switch (statUnitType) {
    case 1:
      temp = { ...baseSchema, ...localUnit }
      statUnitSchema = object(temp)
      break
    case 2:
      temp = { ...baseSchema, ...legalUnit }
      statUnitSchema = object(temp)
      break
    case 3:
      temp = { ...baseSchema, ...enterpriseUnit }
      statUnitSchema = object(temp)
      break
    case 4:
      temp = { ...baseSchema, ...enterpriseGroup }
      statUnitSchema = object(temp)
      break
    default:
      statUnitSchema = object(baseSchema)
      break
  }
  return statUnitSchema
}

export default { getSchema }
