import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'
import { map, pipe } from 'ramda'

import { formBody as bodyPropTypes } from 'components/createSchemaFormHoc/propTypes'
import FormSection from './FormSection'
import FieldGroup from './FieldGroup'
import Field from './Field'
import getSectioned from './getSectioned'

const renderGroup = group => (
  <FieldGroup key={group.key} isExtended={group.isExtended}>
    {group.fieldsMeta.map(Field)}
  </FieldGroup>
)

const renderSection = localize => section => (
  <FormSection key={section.key} id={section.key} title={localize(section.key)}>
    {section.groups.map(renderGroup)}
  </FormSection>
)

const FormBody = ({
  values,
  touched,
  getFieldErrors,
  isSubmitting,
  setFieldValue,
  handleChange,
  handleBlur,
  fieldsMeta,
  localize,
}) => {
  const toSection = renderSection(localize)
  const toFieldMeta = ([key, value]) => {
    const { selector, isRequired, localizeKey, groupName, writable, ...restProps } = fieldsMeta[key]

    const props = {
      ...restProps,
      key,
      fieldType: selector,
      name: key,
      value,
      setFieldValue,
      onChange: handleChange,
      onBlur: handleBlur,
      label: localizeKey,
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting || !writable,
      required: isRequired,
      localize,
    }
    return { section: groupName, props }
  }
  const sections = pipe(Object.entries, map(toFieldMeta), getSectioned, map(toSection))(values)
  return <Segment.Group>{sections}</Segment.Group>
}

const { bool, shape, string, number, objectOf } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  fieldsMeta: objectOf(shape({
    selector: number.isRequired,
    localizeKey: string.isRequired,
    isRequired: bool.isRequired,
    groupName: string.isRequired,
  })).isRequired,
}

export default FormBody
