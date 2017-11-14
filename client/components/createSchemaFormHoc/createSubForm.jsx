import React from 'react'
import { Form, Segment, Message, Grid, Icon } from 'semantic-ui-react'
import { pipe, pathOr } from 'ramda'
import { setPropTypes, setDisplayName } from 'recompose'

import { ensureArray, hasValue } from 'helpers/validation'
import { subForm as propTypes } from './propTypes'

const enhance = pipe(setPropTypes(propTypes), setDisplayName('SubForm'))

const createSubForm = Body =>
  enhance((props) => {
    const {
      errors,
      status,
      isValid,
      isSubmitting,
      dirty,
      handleSubmit,
      handleReset,
      handleCancel,
      localize,
    } = props
    const statusErrors = pathOr({}, ['errors'], status)
    const anyErrors = !isValid || hasValue(statusErrors)
    const anySummary = hasValue(statusErrors.summary)
    const getFieldErrors = key => [...ensureArray(errors[key]), ...pathOr([], [key], statusErrors)]
    return (
      <Form onSubmit={handleSubmit} error={anyErrors} style={{ width: '100%' }}>
        <Body {...props} getFieldErrors={getFieldErrors} />
        {anySummary && (
          <Segment id="summary">
            <Message list={statusErrors.summary.map(localize)} error />
          </Segment>
        )}
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
  })

export default createSubForm
