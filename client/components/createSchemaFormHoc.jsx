import React from 'react'
import { Form, Icon, Segment, Message, Grid } from 'semantic-ui-react'
import { pathOr } from 'ramda'
import { Formik } from 'formik'
import { setDisplayName } from 'recompose'

import { collectErrors } from 'helpers/formik'
import { hasValue } from 'helpers/validation'

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
      <Form onSubmit={handleSubmit} error={anyErrors}>
        <Body {...props} getFieldErrors={collectErrors(errors, statusErrors)} />
        {anySummary &&
          <Segment id="summary">
            <Message list={statusErrors.summary.map(localize)} error />
          </Segment>}
        <Grid columns={3} stackable>
          <Grid.Column width={5}>
            <Form.Button
              type="button"
              onClick={handleCancel}
              disabled={isSubmitting}
              content={localize('Back')}
              icon={<Icon size="large" name="chevron left" />}
              floated="left"
            />
          </Grid.Column>
          <Grid.Column textAlign="center" width={6}>
            <Form.Button
              type="button"
              onClick={handleReset}
              disabled={!dirty || isSubmitting}
              content={localize('Reset')}
              icon="undo"
            />
          </Grid.Column>
          <Grid.Column width={5}>
            <Form.Button
              type="submit"
              disabled={isSubmitting}
              content={localize('Submit')}
              icon="check"
              color="green"
              floated="right"
            />
          </Grid.Column>
        </Grid>
      </Form>
    )
  }),
)
