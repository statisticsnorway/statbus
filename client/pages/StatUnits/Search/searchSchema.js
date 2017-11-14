import { object, string, boolean, number } from 'yup'

export default object({
  wildcard: string().default(''),

  type: string().default(''),

  includeLiquidated: boolean().default(false),

  turnoverFrom: number().positive(),

  turnoverTo: number().positive(),

  employeesNumberFrom: number().positive(),

  employeesNumberTo: number().positive(),

  lastChangeFrom: string().default(''),

  lastChangeTo: string()
    .when(['lastChangeFrom', 'lastChangeTo'], {
      is: (lastChangeFrom, lastChangeTo) => lastChangeFrom > lastChangeTo,
      then: string().required('NameIsRequired'),
      otherwise: null,
    })
    .default(''),

  dataSource: string()
    .ensure()
    .default(''),

  regMainActivityId: number()
    .positive()
    .default(null),

  sectorCodeId: number()
    .positive()
    .default(null),

  legalFormId: number()
    .positive()
    .default(null),

  regionId: number()
    .positive()
    .default(null),
})
