import { object, string } from 'yup'

export const schema = object({
  name: string()
    .min(2)
    .required('UserNameIsRequired')
    .default(''),

  currentPassword: string()
    .required('CurrentPasswordIsRequired')
    .default(''),

  newPassword: string().default(''),

  confirmPassword: string()
    .when('newPassword', (value, fieldSchema) =>
      fieldSchema.equals([value], 'NewPasswordNotConfirmed'))
    .default(''),

  phone: string().default(''),

  email: string()
    .email('NotEmail')
    .required('EmailIsRequired')
    .default(''),
})

export const meta = new Map([
  [
    'name',
    {
      type: 'text',
      label: 'UserName',
      placeholder: 'NameValueRequired',
      required: true,
    },
  ],
  [
    'currentPassword',
    {
      type: 'password',
      label: 'CurrentPassword',
      placeholder: 'CurrentPassword',
      required: true,
    },
  ],
  [
    'newPassword',
    {
      type: 'password',
      label: 'NewPassword_LeaveItEmptyIfYouWillNotChangePassword',
      placeholder: 'NewPassword',
      required: false,
    },
  ],
  [
    'confirmPassword',
    {
      type: 'password',
      label: 'ConfirmPassword',
      placeholder: 'ConfirmPassword',
      required: false,
    },
  ],
  [
    'phone',
    {
      type: 'tel',
      label: 'Phone',
      placeholder: 'PhoneValueRequired',
      required: false,
    },
  ],
  [
    'email',
    {
      type: 'email',
      label: 'Email',
      placeholder: 'EmailValueRequired',
      required: true,
    },
  ],
])
