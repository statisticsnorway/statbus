import React from 'react'
import { Form, Segment, Message, Grid, Icon, Header } from 'semantic-ui-react'
import R from 'ramda'

import { ensureArray, hasValue } from 'helpers/validation'
import { subForm as propTypes } from './propTypes'

const unmappedEntries = (from = [], to = []) =>
  Object.entries(from).filter(([key]) => !R.has(key, to))

function createSubForm(Body) {
  function SubForm(props) {
    const {
      errors,
      initialErrors,
      status,
      isSubmitting,
      dirty,
      handleSubmit,
      handleReset,
      onCancel,
      showSummary,
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
    const hasSummaryErrors = hasValue(summary)
    const hasErrors = hasValue(errors)
    const hasUnmappedErrors = hasValue(unmappedErrors)
    return (
      <Form onSubmit={handleSubmit} error style={{ width: '100%' }}>
        <Body {...props} getFieldErrors={getFieldErrors} />
        {(hasUnmappedErrors || hasSummaryErrors || (hasErrors && showSummary)) && (
          <Segment>
            <Header as="h4" content={localize('Summary')} dividing />
            {hasUnmappedErrors && <Message list={unmappedErrors} error />}
            {hasSummaryErrors && <Message list={summary.map(localize)} error />}
            {showSummary && (
              <Message
                content={localize(hasErrors ? 'FixErrorsBeforeSubmit' : 'EnsureErrorsIsFixed')}
                error
              />
            )}
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
  }

  SubForm.propTypes = propTypes

  SubForm.defaultProps = {
    showSummary: false,
  }

  return SubForm
}

export default createSubForm
