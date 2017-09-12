import React from 'react'
import { Form, Icon, Segment, Message } from 'semantic-ui-react'
import { pathOr } from 'ramda'
import { Formik } from 'formik'

import { collectErrors } from 'helpers/formik'
import { hasValue } from 'helpers/schema'

const styles = {
  formRoot: { width: '100%' },
  formButtons: { display: 'flex', justifyContent: 'space-between' },
}

const createFormikWrapper = ({
  schema: validationSchema,
  onSubmit,
  onCancel: handleCancel,
  localize,
  isInitialValid,
  mapPropsToValues,
  validate,
  validateOnBlur,
  validateOnChange,
}) =>
  Body =>
    Formik({
      handleSubmit: onSubmit,
      isInitialValid,
      mapPropsToValues,
      validate,
      validateOnBlur,
      validateOnChange,
      validationSchema,
    })((props) => {
      const statusErrors = pathOr({}, ['errors'], status)
      const anyErrors = !props.isValid || hasValue(statusErrors)
      const anySummary = hasValue(statusErrors.summary)
      const getFieldErrors = collectErrors(props.errors, statusErrors)
      const bodyProps = { ...props, getFieldErrors, localize }
      return (
        <Form onSubmit={props.handleSubmit} error={anyErrors} style={styles.form}>
          <Body {...bodyProps} />
          {anySummary &&
            <Segment id="summary">
              <Message list={statusErrors.summary.map(localize)} error />
            </Segment>}
          <Form.Group style={styles.formButtons}>
            <Form.Button
              type="button"
              onClick={handleCancel}
              disabled={props.isSubmitting}
              content={localize('Back')}
              icon={<Icon size="large" name="chevron left" />}
            />
            <Form.Button
              type="button"
              onClick={props.handleReset}
              disabled={!props.dirty || props.isSubmitting}
              content={localize('Reset')}
              icon="undo"
            />
            <Form.Button
              type="submit"
              disabled={props.isSubmitting}
              content={localize('Submit')}
              icon="check"
              color="green"
            />
          </Form.Group>
        </Form>
      )
    })

export default createFormikWrapper
