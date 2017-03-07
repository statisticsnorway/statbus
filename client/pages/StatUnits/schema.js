import { number, object, string } from 'yup'

const schema = object({

  name: string()
    .ensure()
    .min(2, 'min 2 symbols')
    .max(100, 'max 100 symbols')
    .required('NameIsRequired'),

  enterpriseUnitRegId: number().nullable(true).default(2),
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

})

export default schema
