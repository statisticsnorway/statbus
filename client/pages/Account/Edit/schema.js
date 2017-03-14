import { object, string } from 'yup'

const account = object({

  name: string()
    .min(2)
    .required('NameIsRequired'),

  currentPassword: string()
    .required('CurrentPasswordIsRequired'),

  email: string()
    .email('NotEmail')
    .required('EmailIsRequired'),

})

export default account
