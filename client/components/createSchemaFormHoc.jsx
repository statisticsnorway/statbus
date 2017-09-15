import React from 'react'
import { Form, Icon, Segment, Message } from 'semantic-ui-react'
import { pathOr } from 'ramda'
import { Formik } from 'formik'
import { setDisplayName } from 'recompose'

import { collectErrors } from 'helpers/formik'
import { hasValue } from 'helpers/schema'
import styles from './styles.pcss'

export default validationSchema => Body => Formik(
  {
    validationSchema,
    handleSubmit: (values, { props, setSubmitting, setStatus }) => {
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
    },
    mapPropsToValues: props => props.values,
  },
)(
  setDisplayName('SubForm')((props) => {
    const {
      errors, status, isValid, isSubmitting, dirty,
      handleSubmit, handleReset, handleCancel, localize,
    } = props
    const statusErrors = pathOr({}, ['errors'], status)
    const anyErrors = !isValid || hasValue(statusErrors)
    const anySummary = hasValue(statusErrors.summary)
    return (
      <Form onSubmit={handleSubmit} error={anyErrors} className={styles.root}>
        <Body {...props} getFieldErrors={collectErrors(errors, statusErrors)} />
        {anySummary &&
          <Segment id="summary">
            <Message list={statusErrors.summary.map(localize)} error />
          </Segment>}
        <Form.Group className={styles.buttonGroup}>
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
        </Form.Group>
      </Form>
    )
  }),
)
