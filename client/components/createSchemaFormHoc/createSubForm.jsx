import React from 'react'
import { Form, Segment, Message, Grid, Icon, Header } from 'semantic-ui-react'
import R from 'ramda'
import { setPropTypes, setDisplayName } from 'recompose'

import { ensureArray, hasValue } from 'helpers/validation'
import { subForm as propTypes } from './propTypes'

const enhance = R.pipe(setPropTypes(propTypes), setDisplayName('SubForm'))
const unmappedEntries = (from = [], to = []) =>
  Object.entries(from).filter(([key]) => !R.has(key, to))

const createSubForm = Body =>
  enhance((props) => {
    const {
      errors,
      initialErrors,
      status,
      isSubmitting,
      dirty,
      handleSubmit,
      handleReset,
      onCancel,
      localize,
    } = props
    const { summary, ...statusErrors } = R.pathOr({}, ['errors'], status)
    const unmappedErrors = [
      ...unmappedEntries(errors, props.values),
      ...unmappedEntries(statusErrors, props.values),
      ...unmappedEntries(initialErrors, props.values),
    ].map(([k, v]) => `${localize(k)}: ${localize(v)}`)
    const getFieldErrors = key => [
      ...ensureArray(errors[key]),
      ...R.pathOr([], [key], statusErrors),
      ...R.pathOr([], [key], initialErrors),
    ]
    return (
      <Form onSubmit={handleSubmit} error style={{ width: '100%' }}>
        <Body {...props} getFieldErrors={getFieldErrors} />
        {(hasValue(unmappedErrors) || hasValue(summary) || hasValue(errors)) && (
          <Segment>
            <Header as="h4" content={localize('Summary')} dividing />
            {hasValue(unmappedErrors) && <Message list={unmappedErrors} error />}
            {hasValue(summary) && <Message list={summary.map(localize)} error />}
            <Message
              content={localize(hasValue(errors) ? 'FixErrorsBeforeSubmit' : 'EnsureErrorsIsFixed')}
              error
            />
          </Segment>
        )}
        <Grid columns={3} stackable>
          <Grid.Column width={5}>
            <Form.Button
              type="button"
              onClick={onCancel}
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
