import React from 'react'
import PropTypes from 'prop-types'
import { Form, Icon } from 'semantic-ui-react'
import { Formik } from 'formik'

import PlainTextField from 'components/fields/TextField'
import withDebounce from 'components/fields/withDebounce'
import { shapeOf, createBasePropTypes } from 'helpers/formikPropTypes'
import schema from './schema'
import styles from './styles.pcss'

const TextField = withDebounce(PlainTextField)

const EditDetails = ({
  values,
  errors,
  status,
  touched,
  dirty,
  isSubmitting,
  isValid,
  setFieldValue,
  handleBlur,
  handleSubmit,
  handleReset,
  handleCancel,
  localize,
}) => (
  <div>
    <h2>{this.props.localize('EditAccount')}</h2>
    <div className={styles.accountEdit}>
      <Form onSubmit={handleSubmit} className={styles.form}>
        <TextField
          name="name"
          setFieldValue={setFieldValue}
          label={localize('UserName')}
          placeholder={localize('NameValueRequired')}
          required
        />
        <TextField
          name="currentPassword"
          setFieldValue={setFieldValue}
          type="password"
          label={localize('CurrentPassword')}
          placeholder={localize('CurrentPassword')}
          required
        />
        <TextField
          name="newPassword"
          setFieldValue={setFieldValue}
          type="password"
          label={localize('NewPassword_LeaveItEmptyIfYouWillNotChangePassword')}
          placeholder={localize('NewPassword')}
        />
        <TextField
          name="confirmPassword"
          setFieldValue={setFieldValue}
          type="password"
          label={localize('ConfirmPassword')}
          placeholder={localize('ConfirmPassword')}
        />
        <TextField
          name="phone"
          setFieldValue={setFieldValue}
          type="tel"
          label={localize('Phone')}
          placeholder={localize('PhoneValueRequired')}
        />
        <TextField
          name="email"
          setFieldValue={setFieldValue}
          type="email"
          label={localize('Email')}
          placeholder={localize('EmailValueRequired')}
          required
        />
        <Form.Button
          type="button"
          onClick={handleCancel}
          disabled={isSubmitting}
          content={localize('Back')}
          icon={<Icon size="large" name="chevron left" />}
        />
        <Form.Button
          type="button"
          onClick={handleReset}
          disabled={!dirty || isSubmitting}
          content={localize('Reset')}
          icon="undo"
        />
        <Form.Button
          type="submit"
          disabled={isSubmitting}
          content={localize('Submit')}
          icon="check"
          color="green"
        />
      </Form>
    </div>
  </div>
)

const { string } = PropTypes
const fields = ['name', 'currentPassword', 'newPassword', 'confirmPassword', 'phone', 'email']
const fieldsOf = shapeOf(fields)
EditDetails.propTypes = {
  ...createBasePropTypes(fields),
  values: fieldsOf(string).isRequired,
}

EditDetails.defaultProps = {
  status: {},
}

export default Formik({
  mapPropsToValues: props => props.formData,
  validationSchema: schema,
  handleSubmit: (values, formikBag) => {
    formikBag.props.submitAccount(values, formikBag)
  },
})(EditDetails)
