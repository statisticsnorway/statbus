import React from 'react'
import { Form } from 'semantic-ui-react'

const Wrapper = ({ schema, onSubmit, setErrors, ...rest }) => {
  const handleSubmit = (e, { formData }) => {
    e.persist()
    e.preventDefault()
    if (schema) {
      schema
        .validate(formData, { abortEarly: false })
        .then(() => {
          if (setErrors) setErrors({})
          onSubmit(e)
        })
        .catch((err) => {
          if (setErrors) {
            const errors = err.inner.reduce(
              (prev, cur) => ({ ...prev, [cur.path]: cur.errors }),
              {},
            )
            setErrors(errors)
          }
        })
    } else {
      onSubmit(e)
    }
  }
  return (
    <Form {...rest} onSubmit={handleSubmit} />
  )
}

Wrapper.defaultProps = {
  schema: undefined,
  setErrors: undefined,
}

const { func, object } = React.PropTypes

Wrapper.propTypes = {
  schema: object, // eslint-disable-line react/forbid-prop-types
  onSubmit: func.isRequired,
  setErrors: func,
}

export default Wrapper
