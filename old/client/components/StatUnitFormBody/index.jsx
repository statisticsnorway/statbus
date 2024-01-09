import React, { Component } from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'
import { map, pipe } from 'ramda'

import { formBody as bodyPropTypes } from '/components/createSchemaFormHoc/propTypes'
import FormSection from './FormSection.jsx'
import FieldGroup from './FieldGroup.jsx'
import Field from './Field.jsx'
import getSectioned from './getSectioned.js'

class FormBody extends Component {
  renderGroup = group => (
    <FieldGroup key={group.key} isExtended={group.isExtended}>
      {group.fieldsMeta.map(Field)}
    </FieldGroup>
  )

  renderSection = section => (
    <FormSection key={section.key} id={section.key} title={this.props.localize(section.key)}>
      {section.groups.map(this.renderGroup)}
    </FormSection>
  )

  toFieldMeta = ([key, value]) => {
    const {
      selector,
      isRequired,
      localizeKey,
      groupName,
      writable,
      popupLocalizedKey,
      ...restProps
    } = this.props.fieldsMeta[key]

    const props = {
      ...restProps,
      key,
      fieldType: selector,
      name: key,
      value,
      setFieldValue: this.props.setFieldValue,
      onChange: this.props.handleChange,
      onBlur: this.props.handleBlur,
      label: localizeKey,
      touched: !!this.props.touched[key],
      errors: this.props.getFieldErrors(key),
      disabled: this.props.isSubmitting || !writable,
      required: isRequired,
      localize: this.props.localize,
      locale: this.props.locale,
      popuplocalizedKey: popupLocalizedKey,
      regId: this.props.regId,
    }

    return { section: groupName, props }
  }

  render() {
    const sections = pipe(
      Object.entries,
      map(this.toFieldMeta),
      getSectioned,
      map(this.renderSection),
    )(this.props.values)

    return <Segment.Group>{sections}</Segment.Group>
  }
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
