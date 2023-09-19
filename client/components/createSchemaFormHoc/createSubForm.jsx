import React, { useState, useEffect } from 'react'
import { Form, Segment, Message, Grid, Icon, Header, Loader } from 'semantic-ui-react'
import R from 'ramda'
import { ensureArray, hasValue } from 'helpers/validation'
import { capitalizeFirstLetter } from 'helpers/string'
import { subForm as propTypes } from './propTypes'
import styles from './styles.pcss'
import regeneratorRuntime from 'regenerator-runtime'

const unmappedEntries = (from = [], to = []) =>
  Object.entries(from).filter(([key]) => !R.has(key, to))

function createSubForm(Body, showReset) {
  function SubForm(props) {
    const [errors, setErrors] = useState({})
    const [initialErrors, setInitialErrors] = useState({})
    const [status, setStatus] = useState({})
    const [isSubmitting, setIsSubmitting] = useState(false)
    const [dirty, setDirty] = useState(false)
    const { localize } = props

    useEffect(() => {
      // Initialize errors, initialErrors, and status from props
      setErrors(props.errors)
      setInitialErrors(props.initialErrors)
      setStatus(props.status)

      // Update the dirty state based on props.values
      const isFormDirty = Object.keys(props.values).some(key => props.values[key] !== props.initialValues[key])
      setDirty(isFormDirty)
    }, [props.errors, props.initialErrors, props.status, props.values, props.initialValues])

    const unmappedErrors = [
      ...unmappedEntries(errors, props.values),
      ...unmappedEntries(props.errors, props.values),
      ...unmappedEntries(initialErrors, props.values),
    ].map(([k, v]) =>
      k === 'message' ? `${localize(v)}` : `${localize(capitalizeFirstLetter(k))}: ${localize(v)}`)

    const getFieldErrors = key => [
      ...ensureArray(errors[key]),
      ...R.pathOr([], ['errors', key], status),
      ...R.pathOr([], [key], initialErrors),
    ]

    const hasSummaryErrors = hasValue(props.summary)
    const hasErrors = hasValue(errors)
    const hasUnmappedErrors = hasValue(unmappedErrors)

    const onReset = () => {
      // Reset the form values and clear errors
      props.resetForm()
      setTimeout(() => {
        setErrors({})
      }, 0)
    }

    const handleSubmit = async (e) => {
      e.preventDefault()
      setIsSubmitting(true)

      try {
        // Perform form submission logic here
        // If successful, you can redirect or perform other actions
      } catch (error) {
        // Handle submission error here and update errors using setErrors
      } finally {
        setIsSubmitting(false)
      }
    }

    return (
      <Form onSubmit={handleSubmit} error style={{ width: '100%' }}>
        <Body {...props} getFieldErrors={getFieldErrors} />

        {(hasUnmappedErrors || hasSummaryErrors || (hasErrors && props.showSummary)) && (
          <Segment>
            <Header as="h4" content={localize('Summary')} dividing />
            {hasUnmappedErrors && <Message list={unmappedErrors} error />}
            {hasSummaryErrors && <Message list={status.summary.map(localize)} error />}
            {props.showSummary && hasErrors && (
              <Message content={localize('FixErrorsBeforeSubmit')} error />
            )}
          </Segment>
        )}
        <Grid columns={3} stackable className={styles['btn-group']}>
          <Grid.Column width={5}>
            <Form.Button
              type="button"
              onClick={props.onCancel}
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
