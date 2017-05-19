import { object, string } from 'yup'

export default object({

  name: string()
    .min(2)
    .required('UserNameIsRequired')
    .default(''),

  currentPassword: string()
    .required('CurrentPasswordIsRequired')
    .default(''),

  newPassword: string()
    .default(''),

  confirmPassword: string()
    .when('newPassword', (value, schema) =>
      schema.equals([value], 'NewPasswordNotConfirmed'))
    .default(''),

  phone: string()
    .default(''),

  email: string()
    .email('NotEmail')
    .required('EmailIsRequired')
    .default(''),

})
