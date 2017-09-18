import { Formik } from 'formik'
import { pipe, prop } from 'ramda'

import createSubForm from './createSubForm'

const handleSubmit = (
  values,
  { props, setSubmitting, setStatus },
) => {
  props.onSubmit(
    values,
    {
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
    },
  )
}

export default (
  validationSchema,
  mapPropsToValues = prop('values'),
) => pipe(
  createSubForm,
  Formik({ validationSchema, mapPropsToValues, handleSubmit }),
)
