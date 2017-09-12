export const meta = new Map([
  ['name', {
    type: 'text',
    label: 'UserName',
    placeholder: 'NameValueRequired',
    required: true,
  }],
  ['currentPassword', {
    type: 'password',
    label: 'CurrentPassword',
    placeholder: 'CurrentPassword',
    required: true,
  }],
  ['newPassword', {
    type: 'password',
    label: 'NewPassword_LeaveItEmptyIfYouWillNotChangePassword',
    placeholder: 'NewPassword',
    required: false,
  }],
  ['confirmPassword', {
    type: 'password',
    label: 'ConfirmPassword',
    placeholder: 'ConfirmPassword',
    required: false,
  }],
  ['phone', {
    type: 'tel',
    label: 'Phone',
    placeholder: 'PhoneValueRequired',
    required: false,
  }],
  ['email', {
    type: 'email',
    label: 'Email',
    placeholder: 'EmailValueRequired',
    required: true,
  }],
])

export const names = [...meta.keys()]
