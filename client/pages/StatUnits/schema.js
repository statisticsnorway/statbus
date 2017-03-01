import { number, object, string } from 'yup'

const schema = object({

  name: string()
    .ensure()
    .min(2, 'min 2 symbols')
    .max(25, 'max 25 symbols')
    .required('NameIsRequired'),

  employees: number()
    .integer()
    .positive()
    .max(30, 'StatUnitEmployeesMax'),

  numOfPeople: number()
    .integer()
    .positive()
    .min(5, 'num of people 5 min')
    .max(30, 'StatUnitNumOfPeopleMax'),

})

export default schema
