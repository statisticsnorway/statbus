import React from 'react'
import PropTypes from 'prop-types'
import { Form, Icon, Message, Segment } from 'semantic-ui-react'
import { pipe, map, pathOr } from 'ramda'

import { collectErrors, createBasePropTypes } from 'helpers/formik'
import { hasValue } from 'helpers/schema'
import FormSection from './FormSection'
import FieldGroup from './FieldGroup'
import Field from './Field'
import groupFieldMetaBySections from './getSectioned'
import styles from './styles.pcss'

const SubForm = ({
  values,
  touched,
  isValid,
  errors,
  status,
  dirty,
  isSubmitting,
  setFieldValue,
  handleChange,
  handleBlur,
  handleSubmit,
  handleReset,
  handleCancel,
  fieldsMeta,
  localize,
}) => {
  const statusErrors = pathOr({}, ['errors'], status)
  const getFieldErrors = collectErrors(errors, statusErrors)
  const anyErrors = !isValid || hasValue(statusErrors)
  const anySummary = hasValue(statusErrors.summary)
  const toFieldMeta = ([key, value]) => {
    const {
      selector: type, isRequired: required, localizeKey: label, groupName: section,
      ...restProps
    } = fieldsMeta[key]
    const props = {
      ...restProps,
      key,
      fieldType: type,
      name: key,
      value,
      setFieldValue,
      onChange: handleChange,
      onBlur: handleBlur,
      label,
      placeholder: label,
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting,
      required,
      localize,
    }
    return { section, props }
  }
  const sections = pipe(
    Object.entries,
    map(toFieldMeta),
    groupFieldMetaBySections,
  )(values)
  return (
    <Form
      onSubmit={handleSubmit}
      error={anyErrors}
      className={styles['form-root']}
    >
      {sections.map(section => (
        <FormSection key={section.key} id={section.key} title={localize(section.key)}>
          {section.groups.map(group => (
            <FieldGroup key={group.key} isExtended={group.isExtended}>
              {group.fieldsMeta.map(Field)}
            </FieldGroup>
          ))}
        </FormSection>
      ))}
      {anySummary &&
        <Segment id="summary">
          <Message list={statusErrors.summary.map(localize)} error />
        </Segment>}
      <Form.Group className={styles['form-buttons']}>
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
}

const { bool, shape, string, number, objectOf } = PropTypes
SubForm.propTypes = {
  ...createBasePropTypes([]),
  fieldsMeta: objectOf(shape({
    selector: number.isRequired,
    localizeKey: string.isRequired,
    isRequired: bool.isRequired,
    groupName: string.isRequired,
  })).isRequired,
}

SubForm.defaultProps = {
  status: undefined,
}

export default SubForm
