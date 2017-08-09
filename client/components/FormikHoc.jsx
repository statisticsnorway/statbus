import React from 'react'
import { Formik } from 'formik'
import { Form, Message } from 'semantic-ui-react'

const SchemaForm = ({
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
}) => {
  const reducer = (prev, [key, value]) => {
    const hasError = errors[key] && touched[key]
    const curr = [
      ...prev,
      <Form.Field
        key={`${key}_inp`}
        id={key}
        name={key}
        value={value}
        onChange={handleChange}
        onBlur={handleBlur}
        type="text"
        label={key}
        placeholder={`Enter ${key}`}
        error={hasError}
        inline
      />,
    ]
    if (hasError) {
      curr.push(<Message key={`${key}_err`} content={errors[key]} error />)
    }
    return curr
  }
  return (
    <Form onSubmit={handleSubmit} error={isValid}>
      {Object.entries(values).reduce(reducer, [])}
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

export default ({
  mapPropsToValues = props => props,
  validationSchema = {},
  handleSubmit = (values, formikBag) => { },
}) => Formik({
  mapPropsToValues,
  validationSchema,
  handleSubmit,
})(SchemaForm)
