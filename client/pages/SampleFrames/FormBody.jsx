import React from 'react'
import PropTypes from 'prop-types'
import { Grid, Message, Tab, Form } from 'semantic-ui-react'

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
  isEdit,
  numberMount,
  incNumberMount,
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
      isEdit={isEdit}
      numberMount={numberMount}
      incNumberMount={incNumberMount}
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
    <div>
      <br />
      <Grid>
        <Grid.Row>
          <Form.Group widths="equal" style={{ width: '100%' }}>
            <Form.Input
              {...propsFor('name')}
              label={localize('Name')}
              placeholder={localize('NameIsRequired')}
              required
            />
            <Form.Input
              {...propsFor('description')}
              label={localize('Description')}
              placeholder={localize('Description')}
            />
          </Form.Group>
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
    </div>
  )
}

const { arrayOf, number, shape, string } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shape({
    name: string.isRequired,
    description: string,
    fields: arrayOf(number).isRequired,
    predicate: predicatePropTypes.isRequired,
  }).isRequired,
}

export default FormBody
