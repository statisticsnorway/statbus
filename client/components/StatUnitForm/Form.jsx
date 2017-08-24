import React from 'react'
import PropTypes from 'prop-types'
import { Form, Icon } from 'semantic-ui-react'
import { pipe, map } from 'ramda'

import { ensureErrors } from 'helpers/schema'
import Section from './Section'
import groupFieldMetaBySections from './getSectioned'
import styles from './styles.pcss'

const StatUnitForm = ({
  values,
  touched,
  isValid,
  errors,
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
  const toFieldMeta = ([key, value]) => {
    const {
      selector: type, isRequired: required, localizeKey: label,
      groupName: section, ...restProps
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
      errors: ensureErrors(errors[key]),
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
    map(s => <Section key={s.key} title={localize(s.key)} content={s.value} />),
  )(values)
  return (
    <Form
      onSubmit={handleSubmit}
      error={!isValid}
      className={styles['form-root']}
    >
      {sections}
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
StatUnitForm.propTypes = {
  values: shape({}).isRequired,
  touched: shape({}).isRequired,
  isValid: bool.isRequired,
  errors: shape({}).isRequired,
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

export default StatUnitForm
