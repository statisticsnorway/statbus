import React from 'react'
import PropTypes from 'prop-types'
import { Form, Icon } from 'semantic-ui-react'
import { pipe, map, isEmpty, pathOr } from 'ramda'

import { ensureErrors } from 'helpers/schema'
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
      errors: [...ensureErrors(errors[key]), ...pathOr([], [key], statusErrors)],
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
  const hasErrors = !isValid || !isEmpty(statusErrors)
  return (
    <Form
      onSubmit={handleSubmit}
      error={hasErrors}
      className={styles['form-root']}
    >
      {sections.map(section => (
        <FormSection key={section.key} title={localize(section.key)}>
          {section.groups.map(group => (
            <FieldGroup key={group.key} isExtended={group.isExtended}>
              {group.fieldsMeta.map(Field)}
            </FieldGroup>
          ))}
        </FormSection>
      ))}
      <Form.Group className={styles['form-buttons']}>
        <Form.Button
          type="button"
          onClick={handleCancel}
          disabled={isSubmitting}
          content="Cancel"
          icon={<Icon size="large" name="chevron left" />}
        />
        <Form.Button
          type="button"
          onClick={handleReset}
          disabled={!dirty || isSubmitting}
          icon="undo"
          content="Reset"
        />
        <Form.Button
          type="submit"
          disabled={isSubmitting}
          content="Submit"
          icon="check"
          color="green"
        />
      </Form.Group>
    </Form>
  )
}

const { bool, shape, string, number, func, objectOf } = PropTypes
SubForm.propTypes = {
  values: shape({}).isRequired,
  touched: shape({}).isRequired,
  isValid: bool.isRequired,
  errors: shape({}).isRequired,
  status: shape({
    errors: shape({}),
  }),
  dirty: bool.isRequired,
  isSubmitting: bool.isRequired,
  fieldsMeta: objectOf(shape({
    selector: number.isRequired,
    localizeKey: string.isRequired,
    isRequired: bool.isRequired,
    groupName: string.isRequired,
  })).isRequired,
  handleChange: func.isRequired,
  setFieldValue: func.isRequired,
  handleBlur: func.isRequired,
  handleSubmit: func.isRequired,
  handleReset: func.isRequired,
  handleCancel: func.isRequired,
  localize: func.isRequired,
}

SubForm.defaultProps = {
  status: undefined,
}

export default SubForm
