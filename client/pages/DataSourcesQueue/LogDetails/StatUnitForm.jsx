import React from 'react'
import PropTypes from 'prop-types'
import Yup from 'yup'
import { Form } from 'semantic-ui-react'
import { Formik } from 'formik'

const TheForm = ({
  values,
  touched,
  isValid,
  errors,
  dirty,
  isSubmitting,
  handleChange,
  handleBlur,
  handleSubmit,
  handleReset,
  handleCancel,
  fieldsMeta,
  localize,
}) => {
  const byGroup = (prev, [key, value]) => {
    const { type, required, label, placeholder, group } = fieldsMeta[key]
    const FieldComponent = getFieldComopnent(
      type,
      key,
      value,
      handleChange,
      handleBlur,
      label,
      placeholder,
      touched[key],
      errors[key],
      required,
      localize,
    )
    return {
      ...prev,
      [group]: [...prev[group] || [], <FieldComponent />],
    }
  }
  return (
    <Form onSubmit={handleSubmit} error={!isValid}>
      {Object.values(Object.entries(values).reduce(byGroup, {}))}
      <Form.Button
        type="button"
        onClick={handleCancel}
        disabled={isSubmitting}
        icon="arrow_left"
        content="Cancel"
      />
      <Form.Button
        type="button"
        onClick={handleReset}
        disabled={!dirty || isSubmitting}
        icon="reload"
        content="Reset"
      />
      <Form.Button
        type="submit"
        disabled={isSubmitting}
        content="Submit"
        icon="check"
        color="green"
      />
    </Form>
  )
}

const { bool, shape, string, number, func } = PropTypes
TheForm.propTypes = {
  values: shape({}).isRequired,
  touched: shape({}).isRequired,
  isValid: bool.isRequired,
  errors: shape({}).isRequired,
  dirty: bool.isRequired,
  isSubmitting: bool.isRequired,
  fieldsMeta: shape({
    type: number.isRequired,
    label: string.isRequired,
    required: bool.isRequired,
    group: string.isRequired,
    placeholder: string,
  }).isRequired,
  handleChange: func.isRequired,
  handleBlur: func.isRequired,
  handleSubmit: func.isRequired,
  handleReset: func.isRequired,
  handleCancel: func.isRequired,
  localize: func.isRequired,
}

const validationSchema = Yup.object({
  name: Yup.string().required(),
  statId: Yup.string().required(),
  shortName: Yup.string(),
})

export default Formik({
  validationSchema,
  mapPropsToValues: props => props,
  handleSubmit: (...params) => {
    console.log(params)
  },
})(TheForm)
