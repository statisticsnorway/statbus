import { withFormik } from 'formik'
import { pipe, prop } from 'ramda'

import createSubForm from './createSubForm'

const handleSubmit = (values, { props: { onSubmit, ...props }, setSubmitting, setStatus }) => {
  onSubmit(values, {
    props,
    started: () => {
      setSubmitting(true)
    },
    succeeded: () => {
      setSubmitting(false)
    },
    failed: (errors) => {
      setSubmitting(false)
      setStatus({ errors })
    },
  })
}

export default (validationSchema, mapPropsToValues = prop('values')) =>
  pipe(createSubForm, withFormik({ validationSchema, mapPropsToValues, handleSubmit }))
