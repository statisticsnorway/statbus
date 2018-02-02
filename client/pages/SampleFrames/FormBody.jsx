import React from 'react'
import PropTypes from 'prop-types'
import { Grid, Message, Tab } from 'semantic-ui-react'

import { formBody as bodyPropTypes } from 'components/createSchemaFormHoc/propTypes'
import { TextField as PlainTextField, withDebounce } from 'components/fields'
import handlerFor from 'helpers/handleSetFieldValue'
import { hasValue } from 'helpers/validation'
import PredicateEditor from './PredicateEditor'
import FieldsEditor from './FieldsEditor'
import { predicate as predicatePropTypes } from './propTypes'

const TextField = withDebounce(PlainTextField)

const FormBody = ({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  handleBlur,
  localize,
}) => {
  const propsFor = key => ({
    name: key,
    value: values[key],
    touched: !!touched[key],
    errors: getFieldErrors(key),
    disabled: isSubmitting,
    onChange: handlerFor(setFieldValue),
    onBlur: handleBlur,
    localize,
  })
  const predicateProps = propsFor('predicate')
  const fieldsProps = propsFor('fields')
  const renderPredicateEditor = () => (
    <PredicateEditor
      value={values.predicate}
      onChange={value => setFieldValue('predicate', value)}
      localize={localize}
    />
  )
  const renderFieldsEditor = () => (
    <FieldsEditor
      value={values.fields}
      onChange={value => setFieldValue('fields', value)}
      localize={localize}
    />
  )
  return (
    <Grid>
      <Grid.Row>
        <Grid.Column width={6}>
          <TextField {...propsFor('name')} label="Name" placeholder="NameIsRequired" required />
        </Grid.Column>
      </Grid.Row>
      <Grid.Row
        as={Tab}
        panes={[
          { menuItem: localize('Predicate'), render: renderPredicateEditor },
          { menuItem: localize('Fields'), render: renderFieldsEditor },
        ]}
      />
      {hasValue(predicateProps.errors) && (
        <Message list={predicateProps.errors.map(localize)} error />
      )}
      {hasValue(fieldsProps.errors) && <Message list={fieldsProps.errors.map(localize)} error />}
    </Grid>
  )
}

const { arrayOf, number, shape, string } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shape({
    name: string.isRequired,
    fields: arrayOf(number).isRequired,
    predicate: predicatePropTypes.isRequired,
  }).isRequired,
}

export default FormBody
