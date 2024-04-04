import React from 'react'
import { Form, Segment, Message, Grid, Icon, Header, Loader } from 'semantic-ui-react'
import * as R from 'ramda'
import { ensureArray, hasValue } from 'helpers/validation.js'
import { capitalizeFirstLetter } from 'helpers/string.js'
import { subForm as propTypes } from './propTypes.js'
import styles from '/components/styles.scss'

const unmappedEntries = (from = [], to = []) =>
  Object.entries(from).filter(([key]) => !R.has(key, to))

function createSubForm(Body, showReset) {
  function SubForm(props) {
    const {
      errors,
      initialErrors,
      status,
      isSubmitting,
      dirty,
      handleSubmit,
      onCancel,
      showSummary,
      localize,
      setErrors,
      resetForm,
    } = props
    const { summary, ...statusErrors } = R.pathOr({}, ['errors'], status)
    const unmappedErrors = [
      ...unmappedEntries(errors, props.values),
      ...unmappedEntries(statusErrors, props.values),
      ...unmappedEntries(initialErrors, props.values),
    ].map(([k, v]) =>
      k === 'message' ? `${localize(v)}` : `${localize(capitalizeFirstLetter(k))}: ${localize(v)}`)
    const getFieldErrors = key => [
      ...ensureArray(errors[key]),
      ...R.pathOr([], [key], statusErrors),
      ...R.pathOr([], [key], initialErrors),
    ]
    const hasSummaryErrors = hasValue(summary)
    const hasErrors = hasValue(errors)
    const hasUnmappedErrors = hasValue(unmappedErrors)

    const onReset = () => {
      resetForm()
      setTimeout(() => {
        setErrors({})
      }, 0)
    }

    return (
      <Form onSubmit={handleSubmit} error style={{ width: '100%' }}>
        <Body {...props} getFieldErrors={getFieldErrors} />

        {(hasUnmappedErrors || hasSummaryErrors || (hasErrors && showSummary)) && (
          <Segment>
            <Header as="h4" content={localize('Summary')} dividing />
            {hasUnmappedErrors && <Message list={unmappedErrors} error />}
            {hasSummaryErrors && <Message list={summary.map(localize)} error />}
            {showSummary && hasErrors && (
              <Message content={localize('FixErrorsBeforeSubmit')} error />
            )}
          </Segment>
        )}
        <Grid columns={3} stackable className={styles['btn-group']}>
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
            {showReset && (
              <Form.Button
                type="reset"
                onClick={onReset}
                disabled={!dirty || isSubmitting}
                content={localize('Reset')}
                icon="undo"
              />
            )}
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
            <div className="submitLoader">
              {isSubmitting && <Loader inline active size="small" />}
            </div>
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

const createSubFormWrapper = showReset => Body => createSubForm(Body, showReset)

export default createSubFormWrapper
