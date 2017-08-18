import React from 'react'
import PropTypes from 'prop-types'
import { Form, Icon } from 'semantic-ui-react'
import { pipe, map } from 'ramda'

import { ensureErrors } from 'helpers/schema'
import Section from './Section'
import getField from './getField'
import getSectioned from './getSectioned'

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
  const toFieldWithMeta = ([key, value]) => {
    const {
      selector: type, isRequired: required, localizeKey: label,
      groupName: section, ...restProps
    } = fieldsMeta[key]
    const component = getField(
      type,
      {
        key,
        name: key,
        value,
        setFieldValue,
        onChange: handleChange,
        onBlur: handleBlur,
        label,
        placeholder: label,
        touched: !!touched[key],
        errors: ensureErrors(errors[key]),
        required,
        localize,
        ...restProps,
      },
    )
    return { section, type, component }
  }
  const sections = pipe(
    Object.entries,
    map(toFieldWithMeta),
    getSectioned,
    map(s => <Section key={s.key} title={localize(s.key)} content={s.value} />),
  )(values)
  return (
    <Form onSubmit={handleSubmit} error={!isValid}>
      {sections}
      <Form.Button
        type="button"
        onClick={handleCancel}
        disabled={isSubmitting}
        content="Cancel"
        icon={<Icon size="large" name="chevron left" />}
        floated="left"
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
        floated="right"
      />
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
