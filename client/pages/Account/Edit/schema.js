import { object, string } from 'yup'

const account = object({

  name: string()
    .required('NameIsRequired'),

  currentPassword: string()
    .required('CurrentPasswordIsRequired'),

  email: string()
    .email('NotEmail')
    .required('EmailIsRequired'),

})

export default account
